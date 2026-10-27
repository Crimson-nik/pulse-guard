/// Camera Service — Flutter ↔ Native Kotlin bridge
///
/// Communicates with the native CameraX ImageAnalysis layer via
/// a MethodChannel (for control commands) and an EventChannel
/// (for streaming per-frame Red/Green average values).
///
/// IMPORTANT — single subscription
/// ------------------------------
/// `receiveBroadcastStream()` is subscribed to exactly ONCE, for the whole
/// life of the app. Previously every `startCapture()` opened a brand new
/// subscription, and the native `onCancel` of the previous one could arrive
/// AFTER the new `onListen`, nulling `eventSink`. That is why the *second*
/// recording showed a frozen / flickering screen while the first one worked.
/// With one permanent subscription the native sink is created once and never
/// lost.

import 'dart:async';
import 'package:flutter/services.dart';

/// Per-frame colour data streamed from the native CameraX analyzer.
class FrameColorData {
  /// Average red channel intensity of the measurement ROI (0–255)
  final double redAvg;

  /// Average green channel intensity of the measurement ROI (0–255)
  final double greenAvg;

  /// Average luma of the ROI (0–255) — what auto-exposure reacts to
  final double lumaAvg;

  /// Fraction of ROI pixels whose red channel is clipped at 250+ (0–1)
  final double clipRatio;

  /// Whether the fingertip is properly covering the lens
  final bool isFingerDetected;

  /// Camera sensor timestamp in nanoseconds (monotonic, uniform-friendly).
  /// Used to build a truly uniform sampling grid; wall-clock time is not good
  /// enough because frames are dropped by the analyser.
  final int timestampNs;

  /// True once auto-exposure and auto-white-balance have been locked.
  /// Recording only starts after this, otherwise the camera's own AWB/AE
  /// feedback loop cancels the pulsatile component (this is what made the
  /// green trace look like a flat line while the finger was pressed).
  final bool exposureLocked;

  const FrameColorData({
    required this.redAvg,
    required this.greenAvg,
    required this.lumaAvg,
    required this.clipRatio,
    required this.isFingerDetected,
    required this.timestampNs,
    required this.exposureLocked,
  });

  factory FrameColorData.fromMap(Map<dynamic, dynamic> map) {
    double d(String k, [double fallback = 0]) {
      final v = map[k];
      if (v is num) return v.toDouble();
      return fallback;
    }

    return FrameColorData(
      redAvg: d('redAvg'),
      greenAvg: d('greenAvg'),
      lumaAvg: d('lumaAvg', d('redAvg')),
      clipRatio: d('clipRatio'),
      isFingerDetected: map['isFingerDetected'] == true,
      timestampNs: (map['timestampNs'] as num?)?.toInt() ?? 0,
      // Default true so an older native build cannot stall the workflow.
      exposureLocked: map['exposureLocked'] != false,
    );
  }
}

/// Service that wraps the native CameraX PPG analyzer.
class CameraService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.pulseguard/ppg_method');
  static const EventChannel _eventChannel =
      EventChannel('com.pulseguard/ppg_stream');

  final StreamController<FrameColorData> _frameController =
      StreamController<FrameColorData>.broadcast();

  StreamSubscription<dynamic>? _subscription;
  Future<bool>? _starting;

  /// Stream of per-frame colour data from the native camera.
  Stream<FrameColorData> get frameStream => _frameController.stream;

  bool _isCapturing = false;
  bool get isCapturing => _isCapturing;

  CameraService() {
    // One subscription for the whole app lifetime — never re-subscribed.
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _frameController.add(FrameColorData.fromMap(event));
        }
      },
      onError: (dynamic error) {
        // ignore: avoid_print
        print('PPG stream error: $error');
      },
    );
  }

  /// Start camera preview with torch on, begin streaming frame data.
  /// Idempotent: a second call while already capturing is a no-op.
  ///
  /// [tuned] applies the camera capture-request tuning (AE/AWB lock, 30 fps
  /// lock, OIS/EIS off). It is applied when the camera is bound, so changing it
  /// only affects the next recording.
  Future<bool> startCapture({bool tuned = true}) {
    if (_isCapturing) return Future<bool>.value(true);
    return _starting ??= _startCaptureInternal(tuned);
  }

  Future<bool> _startCaptureInternal(bool tuned) async {
    try {
      final bool result = await _methodChannel.invokeMethod<bool>(
            'startCapture',
            <String, dynamic>{'tuned': tuned},
          ) ??
          false;
      _isCapturing = result;
      return result;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to start capture: ${e.message}');
      return false;
    } finally {
      _starting = null;
    }
  }

  /// Stop camera preview and torch.
  Future<void> stopCapture() async {
    _isCapturing = false;
    try {
      await _methodChannel.invokeMethod('stopCapture');
    } catch (_) {}
  }

  /// Check if the camera permission is granted.
  Future<bool> hasCameraPermission() async {
    try {
      return await _methodChannel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _isCapturing = false;
    try {
      await _methodChannel.invokeMethod('stopCapture');
    } catch (_) {}
    await _subscription?.cancel();
    _subscription = null;
    await _frameController.close();
  }
}
