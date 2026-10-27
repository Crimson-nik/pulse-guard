/// Camera Service — Flutter ↔ Native Kotlin bridge
///
/// Communicates with the native CameraX ImageAnalysis layer via
/// a MethodChannel (for control commands) and an EventChannel
/// (for streaming per-frame Red/Green average values).

import 'dart:async';
import 'package:flutter/services.dart';

/// Per-frame color data streamed from the native CameraX analyzer.
class FrameColorData {
  /// Average red channel intensity (0–255)
  final double redAvg;

  /// Average green channel intensity (0–255)
  final double greenAvg;

  /// Whether the fingertip is properly covering the lens
  final bool isFingerDetected;

  /// Timestamp in milliseconds since epoch
  final int timestampMs;

  const FrameColorData({
    required this.redAvg,
    required this.greenAvg,
    required this.isFingerDetected,
    required this.timestampMs,
  });

  factory FrameColorData.fromMap(Map<dynamic, dynamic> map) {
    return FrameColorData(
      redAvg: (map['redAvg'] as num).toDouble(),
      greenAvg: (map['greenAvg'] as num).toDouble(),
      isFingerDetected: map['isFingerDetected'] as bool,
      timestampMs: map['timestampMs'] as int,
    );
  }
}

/// Service that wraps the native CameraX PPG analyzer.
class CameraService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.pulseguard/ppg_method');
  static const EventChannel _eventChannel =
      EventChannel('com.pulseguard/ppg_stream');

  StreamSubscription? _subscription;
  final StreamController<FrameColorData> _frameController =
      StreamController<FrameColorData>.broadcast();

  /// Stream of per-frame color data from the native camera.
  Stream<FrameColorData> get frameStream => _frameController.stream;

  bool _isCapturing = false;
  bool get isCapturing => _isCapturing;

  /// Start camera preview with torch on, begin streaming frame data.
  Future<bool> startCapture() async {
    try {
      final bool result =
          await _methodChannel.invokeMethod<bool>('startCapture') ?? false;
      if (result) {
        _isCapturing = true;
        _subscription =
            _eventChannel.receiveBroadcastStream().listen((dynamic event) {
          if (event is Map) {
            _frameController.add(FrameColorData.fromMap(event));
          }
        }, onError: (dynamic error) {
          print('PPG stream error: $error');
        });
      }
      return result;
    } on PlatformException catch (e) {
      print('Failed to start capture: ${e.message}');
      return false;
    }
  }

  /// Stop camera preview and torch.
  Future<void> stopCapture() async {
    try {
      await _methodChannel.invokeMethod('stopCapture');
    } catch (_) {}
    await _subscription?.cancel();
    _subscription = null;
    _isCapturing = false;
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
  void dispose() {
    stopCapture();
    _frameController.close();
  }
}
