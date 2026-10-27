/// Native Android — CameraX PPG Analyzer Plugin
///
/// This Kotlin file handles:
/// 1. CameraX ImageAnalysis — captures YUV_420_888 frames at ~30 FPS
/// 2. Torch control — enables the rear flashlight for PPG illumination
/// 3. Real-time color extraction — computes per-frame average Red and Green
///    channel intensities using subsampled YUV→RGB conversion
/// 4. Finger detection — heuristic based on red-channel dominance
/// 5. Flutter communication — MethodChannel + EventChannel bridge
///
/// Architecture:
///   Flutter UI ←→ MethodChannel (startCapture/stopCapture)
///                  EventChannel  (streams FrameColorData per frame)
///   ↕
///   CameraX ImageAnalysis.Analyzer (native frame processing)

package com.pulseguard.app

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
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
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ─── Method Channel ─────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCapture" -> {
                        startCamera(result)
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

    private fun startCamera(result: MethodChannel.Result) {
        cameraExecutor = Executors.newSingleThreadExecutor()

        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()

                // Build ImageAnalysis use case
                imageAnalysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .build()
                    .also { analysis ->
                        analysis.setAnalyzer(cameraExecutor!!, PpgFrameAnalyzer { frameData ->
                            mainHandler.post {
                                eventSink?.success(frameData)
                            }
                        })
                    }

                // Use the back camera
                val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

                // Unbind any existing use cases
                cameraProvider?.unbindAll()

                // Bind to lifecycle
                camera = cameraProvider?.bindToLifecycle(
                    this as LifecycleOwner,
                    cameraSelector,
                    imageAnalysis
                )

                // Enable torch (flashlight) for PPG illumination
                camera?.cameraControl?.enableTorch(true)

                result.success(true)
            } catch (e: Exception) {
                result.error("CAMERA_ERROR", "Failed to start camera: ${e.message}", null)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun stopCamera() {
        try {
            camera?.cameraControl?.enableTorch(false)
            cameraProvider?.unbindAll()
            cameraExecutor?.shutdown()
            camera = null
            imageAnalysis = null
            cameraProvider = null
        } catch (_: Exception) {}
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
// Extracts average Red and Green channel intensities via subsampled
// YUV→RGB conversion (no Bitmap allocation, minimal GC pressure).
//
// Finger detection heuristic:
//   isFingerCovered = (avgRed > 140) && (avgRed > avgGreen * 1.5)
//
// When a finger covers the lens + flash:
//   - Red channel: 200–250 (skin reflects red strongly)
//   - Green channel: 30–80  (hemoglobin absorbs green)
// Without finger:
//   - Both channels are variable / low / similar

class PpgFrameAnalyzer(
    private val onFrameProcessed: (Map<String, Any>) -> Unit
) : ImageAnalysis.Analyzer {

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

            var totalRed = 0L
            var totalGreen = 0L
            var count = 0

            // Subsample every 8th pixel for performance
            // On a 1920×1080 frame, this processes ~32,400 pixels
            // instead of 2,073,600 — keeping processing under 3ms
            val step = 8

            for (row in 0 until height step step) {
                for (col in 0 until width step step) {
                    // Y plane index (with row stride)
                    val yIndex = row * yRowStride + col

                    // UV plane index (chroma is 2× subsampled)
                    val uvRow = row / 2
                    val uvCol = col / 2
                    val uvIndex = uvRow * uvRowStride + uvCol * uvPixelStride

                    // Safely read bytes
                    if (yIndex >= yPlane.limit() || uvIndex >= uPlane.limit() || uvIndex >= vPlane.limit()) {
                        continue
                    }

                    val y = (yPlane.get(yIndex).toInt() and 0xFF) - 16
                    val u = (uPlane.get(uvIndex).toInt() and 0xFF) - 128
                    val v = (vPlane.get(uvIndex).toInt() and 0xFF) - 128

                    // YUV to RGB (ITU-R BT.601 conversion)
                    val r = ((1.164 * y + 1.596 * v)).toInt().coerceIn(0, 255)
                    val g = ((1.164 * y - 0.813 * v - 0.391 * u)).toInt().coerceIn(0, 255)

                    totalRed += r
                    totalGreen += g
                    count++
                }
            }

            if (count > 0) {
                val avgRed = totalRed.toDouble() / count
                val avgGreen = totalGreen.toDouble() / count

                // Finger placement detection heuristic:
                // When finger covers camera+flash, red is very high and
                // significantly dominates over green (hemoglobin absorption)
                val isFingerDetected = avgRed > 140 && avgRed > avgGreen * 1.5

                val frameData = mapOf<String, Any>(
                    "redAvg" to avgRed,
                    "greenAvg" to avgGreen,
                    "isFingerDetected" to isFingerDetected,
                    "timestampMs" to System.currentTimeMillis()
                )

                onFrameProcessed(frameData)
            }
        } finally {
            image.close()
        }
    }
}
