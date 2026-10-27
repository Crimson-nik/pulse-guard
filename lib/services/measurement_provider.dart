/// Measurement Provider — State management for the PPG capture workflow
///
/// Manages the 30-second capture lifecycle:
///   Idle → Preparing → Capturing → Processing → Complete
///
/// Buffers red/green channel averages from the native camera stream,
/// then passes them to the DSP engine for analysis.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' as drift;

import '../services/camera_service.dart';
import '../services/dsp_engine.dart';
import '../database/app_database.dart';

enum MeasurementState {
  idle,
  preparing, // Waiting for finger detection
  capturing, // 30-second recording in progress
  processing, // Running FFT / BP algorithms
  complete, // Results ready
  error,
}

class MeasurementProvider extends ChangeNotifier {
  final CameraService _camera = CameraService();
  final AppDatabase _db;

  MeasurementProvider(this._db);

  // ─── State ────────────────────────────────────────────────────────────

  MeasurementState _state = MeasurementState.idle;
  MeasurementState get state => _state;

  String _statusMessage = 'Tap to start measurement';
  String get statusMessage => _statusMessage;

  // Capture buffers
  final List<double> _redBuffer = [];
  final List<double> _greenBuffer = [];
  List<double> get redBuffer => List.unmodifiable(_redBuffer);
  List<double> get greenBuffer => List.unmodifiable(_greenBuffer);

  // Timing
  DateTime? _captureStartTime;
  double _elapsedSeconds = 0;
  double get elapsedSeconds => _elapsedSeconds;
  static const double captureDuration = 30.0; // seconds

  // Live finger detection
  bool _fingerDetected = false;
  bool get fingerDetected => _fingerDetected;

  // Latest frame values (for live waveform display)
  double _latestRed = 0;
  double _latestGreen = 0;
  double get latestRed => _latestRed;
  double get latestGreen => _latestGreen;

  // Result
  MeasurementResult? _result;
  MeasurementResult? get result => _result;

  StreamSubscription? _frameSub;
  Timer? _timer;

  // ─── Actions ──────────────────────────────────────────────────────────

  /// Start the measurement workflow.
  Future<void> startMeasurement() async {
    _state = MeasurementState.preparing;
    _statusMessage = 'Place your finger on the camera and flash...';
    _result = null;
    _redBuffer.clear();
    _greenBuffer.clear();
    _elapsedSeconds = 0;
    notifyListeners();

    final started = await _camera.startCapture();
    if (!started) {
      _state = MeasurementState.error;
      _statusMessage = 'Could not access camera. Check permissions.';
      notifyListeners();
      return;
    }

    // Listen to frame stream
    _frameSub = _camera.frameStream.listen(_onFrame);
  }

  /// Cancel an in-progress measurement.
  Future<void> cancelMeasurement() async {
    _timer?.cancel();
    _timer = null;
    await _frameSub?.cancel();
    _frameSub = null;
    await _camera.stopCapture();

    _state = MeasurementState.idle;
    _statusMessage = 'Measurement cancelled';
    _redBuffer.clear();
    _greenBuffer.clear();
    notifyListeners();
  }

  /// Process a frame from the native camera.
  void _onFrame(FrameColorData frame) {
    _latestRed = frame.redAvg;
    _latestGreen = frame.greenAvg;
    _fingerDetected = frame.isFingerDetected;

    if (_state == MeasurementState.preparing) {
      if (frame.isFingerDetected) {
        // Finger detected → begin 30-second capture
        _state = MeasurementState.capturing;
        _statusMessage = 'Hold steady... Recording pulse signal';
        _captureStartTime = DateTime.now();
        _redBuffer.clear();
        _greenBuffer.clear();

        // Start elapsed timer (updates UI every 100ms)
        _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (_captureStartTime != null) {
            _elapsedSeconds = DateTime.now()
                    .difference(_captureStartTime!)
                    .inMilliseconds /
                1000.0;
            notifyListeners();

            if (_elapsedSeconds >= captureDuration) {
              _finishCapture();
            }
          }
        });
      } else {
        _statusMessage = 'Place your finger firmly over camera & flash';
      }
      notifyListeners();
      return;
    }

    if (_state == MeasurementState.capturing) {
      if (!frame.isFingerDetected) {
        // Finger lifted during capture — warn but don't stop
        _statusMessage = '⚠ Keep your finger still!';
      } else {
        _statusMessage =
            'Recording... ${(captureDuration - _elapsedSeconds).toStringAsFixed(0)}s remaining';
      }

      _redBuffer.add(frame.redAvg);
      _greenBuffer.add(frame.greenAvg);
      notifyListeners();
    }
  }

  /// 30 seconds elapsed — stop camera and run DSP algorithms.
  Future<void> _finishCapture() async {
    _timer?.cancel();
    _timer = null;
    await _frameSub?.cancel();
    _frameSub = null;
    await _camera.stopCapture();

    _state = MeasurementState.processing;
    _statusMessage = 'Analyzing pulse signal...';
    notifyListeners();

    // Run DSP on a separate isolate / microtask to avoid UI jank
    try {
      final profile = await _db.getUserProfile();

      final result = DspEngine.runFullPipeline(
        redSignal: _redBuffer.toList(),
        greenSignal: _greenBuffer.toList(),
        durationSeconds: _elapsedSeconds,
        weightKg: profile?.weightKg,
        heightCm: profile?.heightCm,
        age: profile?.age,
      );

      _result = result;

      // Persist to database
      await _db.insertMeasurement(MeasurementsCompanion(
        timestamp: drift.Value(result.timestamp),
        heartRateFft: drift.Value(result.fftResult.heartRate),
        bpmRed: drift.Value(result.fftResult.bpmRed),
        bpmGreen: drift.Value(result.fftResult.bpmGreen),
        confidence: drift.Value(result.fftResult.confidence),
        heartRateSliding: drift.Value(result.slidingResult.heartRate),
        systolic: drift.Value(result.bpResult?.systolic),
        diastolic: drift.Value(result.bpResult?.diastolic),
        pulsePressure: drift.Value(result.bpResult?.pulsePressure),
        strokeVolume: drift.Value(result.bpResult?.strokeVolume),
        bpStage: drift.Value(result.bpResult?.stage),
        totalFrames: drift.Value(result.totalFrames),
        effectiveFps: drift.Value(result.effectiveFps),
        durationSeconds: drift.Value(result.durationSeconds),
      ));

      _state = MeasurementState.complete;
      _statusMessage = 'Analysis complete!';
    } catch (e) {
      _state = MeasurementState.error;
      _statusMessage = 'Analysis failed: ${e.toString()}';
    }
    notifyListeners();
  }

  /// Reset to idle state (after viewing results).
  void reset() {
    _state = MeasurementState.idle;
    _statusMessage = 'Tap to start measurement';
    _result = null;
    _redBuffer.clear();
    _greenBuffer.clear();
    _elapsedSeconds = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _frameSub?.cancel();
    _camera.dispose();
    super.dispose();
  }
}
