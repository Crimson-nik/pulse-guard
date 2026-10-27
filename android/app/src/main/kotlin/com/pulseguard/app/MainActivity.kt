/// Native Android — CameraX PPG Analyzer Plugin
///
/// This Kotlin file handles:
/// 1. CameraX ImageAnalysis — captures YUV_420_888 frames at a locked 30 FPS
/// 2. Torch control — enables the rear LED for PPG illumination
/// 3. Camera tuning for the phone's sensor (tuned for Samsung Galaxy A35 5G:
///    50 MP 1/1.96" main sensor, 0.8 µm pixels, f/1.8, single LED flash)
/// 4. Real-time colour extraction over a CENTRE ROI (no Bitmap allocation)
/// 5. Finger detection + auto-exposure / auto-white-balance locking
/// 6. Flutter communication — MethodChannel + EventChannel bridge
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHY THE CAMERA SETTINGS BELOW MATTER FOR PPG
/// ─────────────────────────────────────────────────────────────────────────
/// A fingertip pulse changes the transmitted light by roughly 0.5–3 %. The
/// phone's camera firmware is designed to *remove* exactly that kind of slow
/// brightness change:
///
///  • AUTO WHITE BALANCE continuously rescales the R/G/B gains to make the
///    scene look neutral. On a red-lit fingertip it keeps re-normalising the
///    green channel, which is what produced a perfectly flat green trace.
///  • AUTO EXPOSURE regulates luma (≈ the green channel) towards a target.
///    Its loop is fast enough (~1 Hz) to partially cancel the pulse itself.
///  • OIS / EIS move and warp the frame, injecting a fake AC component.
///  • Anti-banding + scene modes add further unknown processing.
///
/// So we lock AE and AWB once the finger is steady, and disable stabilisation,
/// scene mode and anti-banding. Exposure is never locked blindly: it is locked
/// only after ~20 stable finger frames, and released again if the image starts
/// clipping, so a hard-pressed (blown-out) finger cannot lock a useless
/// exposure for the whole 30 s.
///
/// NOTE: none of this changes the journal's algorithms. It only gives the DSP
/// a signal that actually contains the pulse.

package com.pulseguard.app

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.os.Handler
import android.os.Looper
import android.util.Range
import android.util.Size
import androidx.annotation.NonNull
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.pulseguard/ppg_method"
    private val EVENT_CHANNEL = "com.pulseguard/ppg_stream"

    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var cameraExecutor: ExecutorService? = null
    private var analyzer: PpgFrameAnalyzer? = null
    private var camera2Control: Camera2CameraControl? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ─── Method Channel ─────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCapture" -> {
                        val tuned = call.argument<Boolean>("tuned") ?: true
                        startCamera(result, tuned)
                    }
                    "stopCapture" -> {
                        stopCamera()
                        result.success(true)
                    }
                    "hasPermission" -> {
                        val granted = ContextCompat.checkSelfPermission(
                            this, Manifest.permission.CAMERA
                        ) == PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    }
                    else -> result.notImplemented()
                }
            }

        // ─── Event Channel (frame data stream) ──────────────────────────
        // The Dart side subscribes exactly once for the app's lifetime, so
        // there is no onListen/onCancel race on the second recording.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Camera Lifecycle
    // ═══════════════════════════════════════════════════════════════════════

    private fun startCamera(result: MethodChannel.Result, tuned: Boolean = true) {
        // Never leak a previous session (this was a source of the 2nd-run hang)
        stopCamera()
        cameraExecutor = Executors.newSingleThreadExecutor()

        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            try {
                val provider = cameraProviderFuture.get()
                cameraProvider = provider

                val bound = bindAnalysis(provider, tuned = tuned)

                // Torch on — the LED is the only light source.
                camera?.cameraControl?.enableTorch(true)

                result.success(bound)
            } catch (e: Exception) {
                stopCamera()
                result.error("CAMERA_ERROR", "Failed to start camera: ${e.message}", null)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    /**
     * Binds ImageAnalysis. If the device rejects any of the tuned capture
     * options (OEMs do reject some keys), we retry with a plain binding so the
     * app still records instead of failing outright.
     */
    private fun bindAnalysis(provider: ProcessCameraProvider, tuned: Boolean): Boolean {
        val builder = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            // 640×480 is the cheapest analysis size. It keeps the ISP from
            // spending time on 12 MP frames (steady 30 FPS) and avoids the
            // heavy downscale smoothing that kills sub-1 % AC variations.
            .setTargetResolution(Size(640, 480))

        if (tuned) {
            try {
                val extender = Camera2Interop.Extender(builder)
                // Constant frame interval → constant sampling frequency.
                extender.setCaptureRequestOption(
                    CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, Range(30, 30)
                )
                // OIS / EIS would move the frame under a stationary finger.
                extender.setCaptureRequestOption(
                    CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
                    CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_OFF
                )
                extender.setCaptureRequestOption(
                    CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
                    CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF
                )
                // Samsung scene/beauty processing is not wanted here.
                extender.setCaptureRequestOption(
                    CaptureRequest.CONTROL_SCENE_MODE,
                    CameraMetadata.CONTROL_SCENE_MODE_DISABLED
                )
                // Single LED source → anti-banding would only modulate exposure.
                extender.setCaptureRequestOption(
                    CaptureRequest.CONTROL_AE_ANTIBANDING_MODE,
                    CameraMetadata.CONTROL_AE_ANTIBANDING_MODE_OFF
                )
            } catch (t: Throwable) {
                // ignore — plain binding below still works
            }
        }

        val analysis: ImageAnalysis = builder.build()
        analysis.setAnalyzer(
            cameraExecutor!!,
            PpgFrameAnalyzer(
                onFrame = { frameData -> mainHandler.post { eventSink?.success(frameData) } },
                onLockChange = { lock -> mainHandler.post { applyExposureLock(lock) } }
            ).also { analyzer = it }
        )
        imageAnalysis = analysis

        val selector = CameraSelector.DEFAULT_BACK_CAMERA
        return try {
            provider.unbindAll()
            camera = provider.bindToLifecycle(
                this as LifecycleOwner, selector, analysis
            )
            camera2Control = try {
                Camera2CameraControl.from(camera!!.cameraControl)
            } catch (t: Throwable) {
                null
            }
            true
        } catch (e: Exception) {
            if (tuned) {
                // Retry without the camera2 tuning options.
                bindAnalysis(provider, tuned = false)
            } else {
                throw e
            }
        }
    }

    /** Locks or releases camera auto-exposure + auto-white-balance. */
    private fun applyExposureLock(lock: Boolean) {
        val c2 = camera2Control
        val an = analyzer
        if (c2 == null) {
            // No camera2 control available: tell the analyser it is "settled"
            // so the capture can start instead of waiting forever.
            an?.exposureLocked = true
            return
        }
        try {
            val options = CaptureRequestOptions.Builder()
                .setCaptureRequestOption(CaptureRequest.CONTROL_AE_LOCK, lock)
                .setCaptureRequestOption(CaptureRequest.CONTROL_AWB_LOCK, lock)
                .build()
            c2.setCaptureRequestOptions(options)
            an?.exposureLocked = lock
        } catch (t: Throwable) {
            an?.exposureLocked = true
        }
    }

    private fun stopCamera() {
        try {
            camera?.cameraControl?.enableTorch(false)
            camera2Control = null
            cameraProvider?.unbindAll()
            cameraExecutor?.shutdown()
        } catch (e: Exception) {
            // ignore
        }
        analyzer = null
        camera = null
        imageAnalysis = null
        cameraProvider = null
        cameraExecutor = null
    }

    override fun onDestroy() {
        stopCamera()
        super.onDestroy()
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// PPG Frame Analyzer
// ═════════════════════════════════════════════════════════════════════════════
//
// Processes each YUV_420_888 frame from CameraX ImageAnalysis.
// Extracts the average Red / Green / Luma of the CENTRE ROI via subsampled
// YUV→RGB conversion (no Bitmap allocation, minimal GC pressure).
//
// The centre ROI (middle 60 %) is used because the LED hotspot sits off-centre
// next to the lens, so the frame edges are much brighter than the tissue over
// the lens — averaging the whole frame mixes two very different exposures.
//
// Finger detection heuristic:
//   isFingerCovered = (avgRed > 120) && (avgRed > avgGreen * 1.35)
//
// When a finger covers the lens + flash:
//   - Red channel:   180–250 (skin + LED reflect red strongly)
//   - Green channel: 30–120  (haemoglobin absorbs green)
// Without finger: the scene is much dimmer and not red-dominant.

class PpgFrameAnalyzer(
    private val onFrame: (Map<String, Any>) -> Unit,
    private val onLockChange: (Boolean) -> Unit
) : ImageAnalysis.Analyzer {

    @Volatile
    var exposureLocked: Boolean = false

    private var stableFingerFrames = 0
    private var clipFrames = 0
    private var unlockCount = 0

    override fun analyze(image: ImageProxy) {
        try {
            val planes = image.planes
            val yPlane = planes[0].buffer
            val uPlane = planes[1].buffer
            val vPlane = planes[2].buffer

            val width = image.width
            val height = image.height
            val yRowStride = planes[0].rowStride
            val uvRowStride = planes[1].rowStride
            val uvPixelStride = planes[1].pixelStride

            val yLimit = yPlane.limit()
            val uLimit = uPlane.limit()
            val vLimit = vPlane.limit()

            // Centre ROI — middle 60 % in both axes
            val x0 = (width * 0.20).toInt()
            val x1 = (width * 0.80).toInt()
            val y0 = (height * 0.20).toInt()
            val y1 = (height * 0.80).toInt()

            var totalRed = 0L
            var totalGreen = 0L
            var totalLuma = 0L
            var clipped = 0
            var count = 0

            // Subsample every 4th pixel of the ROI (~7 k samples at 640×480):
            // cheap enough for <2 ms, dense enough for a stable frame average.
            val step = 4

            var row = y0
            while (row < y1) {
                var col = x0
                while (col < x1) {
                    val yIndex = row * yRowStride + col
                    val uvRow = row / 2
                    val uvCol = col / 2
                    val uvIndex = uvRow * uvRowStride + uvCol * uvPixelStride

                    if (yIndex >= yLimit || uvIndex >= uLimit || uvIndex >= vLimit) {
                        col += step
                        continue
                    }

                    val yRaw = (yPlane.get(yIndex).toInt() and 0xFF)
                    val y = yRaw - 16
                    val u = (uPlane.get(uvIndex).toInt() and 0xFF) - 128
                    val v = (vPlane.get(uvIndex).toInt() and 0xFF) - 128

                    // YUV → RGB (ITU-R BT.601 limited range)
                    val r = (1.164 * y + 1.596 * v).toInt().coerceIn(0, 255)
                    val g = (1.164 * y - 0.813 * v - 0.391 * u).toInt().coerceIn(0, 255)

                    totalRed += r
                    totalGreen += g
                    totalLuma += yRaw
                    if (r >= 250) clipped++
                    count++

                    col += step
                }
                row += step
            }

            if (count > 0) {
                val avgRed = totalRed.toDouble() / count
                val avgGreen = totalGreen.toDouble() / count
                val avgLuma = totalLuma.toDouble() / count
                val clipRatio = clipped.toDouble() / count

                val isFingerDetected = avgRed > 120.0 && avgRed > avgGreen * 1.35

                // ── Automatic AE / AWB lock management ──────────────
                // Locking is only allowed when the exposure actually looks
                // sane. Locking a blown-out (hard-pressed) or a black frame
                // would freeze an exposure in which the pulse is invisible,
                // which shows up as a wrong (too low) BPM.
                if (isFingerDetected) {
                    stableFingerFrames++
                } else {
                    stableFingerFrames = 0
                }

                val lumaSane = avgLuma > 45.0 && avgLuma < 205.0 &&
                    clipRatio < 0.01

                if (!exposureLocked) {
                    // ~0.7 s of a steady finger AND a good exposure: lock.
                    if (stableFingerFrames >= 20 && lumaSane) {
                        onLockChange(true)
                    }
                } else {
                    val bad = clipRatio > 0.08 || avgLuma < 30.0 || avgLuma > 225.0
                    if (bad) clipFrames++ else if (clipFrames > 0) clipFrames--

                    if (clipFrames > 30 && unlockCount < 3) {
                        // Exposure drifted out of range: release it, let AE
                        // re-converge, then re-lock. Capped so it cannot hunt
                        // for the whole recording.
                        clipFrames = 0
                        stableFingerFrames = 0
                        unlockCount++
                        onLockChange(false)
                    }
                }

                val frameData = mapOf<String, Any>(
                    "redAvg" to avgRed,
                    "greenAvg" to avgGreen,
                    "lumaAvg" to avgLuma,
                    "clipRatio" to clipRatio,
                    "isFingerDetected" to isFingerDetected,
                    // Sensor timestamp (ns, monotonic). Much better than
                    // System.currentTimeMillis() for building a uniform
                    // sampling grid — wall-clock time includes Handler delay.
                    "timestampNs" to image.imageInfo.timestamp,
                    "exposureLocked" to exposureLocked
                )

                onFrame(frameData)
            }
        } catch (t: Throwable) {
            // A single bad frame must never kill the analyser.
        } finally {
            image.close()
        }
    }
}
