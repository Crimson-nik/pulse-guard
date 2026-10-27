/// Measurement Provider — State management for the PPG capture workflow
///
/// Manages the 30-second capture lifecycle:
///   Idle → Preparing → Capturing → Processing → Complete
///
/// Buffers red/green channel averages from the native camera stream,
/// then passes them to the DSP engine for analysis.
///
/// Two hard rules that this file enforces:
///  1. A new recording ALWAYS starts from a clean state (the previous result
///     is cleared first). Previously the old `complete` state survived, so the
///     measurement screen instantly re-navigated to the previous result on the
///     second run — that was the "slideshow" glitch.
///  2. `notifyListeners()` is throttled to ~16 Hz instead of 30 Hz. Rebuilding
///     the whole screen for every camera frame starved the UI thread, which in
///     turn made CameraX drop frames — i.e. the jank was also corrupting the
///     signal that the FFT then had to work with.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' as drift;

import '../services/camera_service.dart';
import '../services/dsp_engine.dart';
import '../database/app_database.dart';

enum MeasurementState {
  idle,
  preparing, // Waiting for finger detection + camera 3A to settle
  capturing, // 30-second recording in progress
  processing, // Running FFT / BP algorithms
  complete, // Results ready
  error,
}

class MeasurementProvider extends ChangeNotifier {
  final CameraService _camera = CameraService();
  final AppDatabase _db;

  MeasurementProvider(this._db) {
    // Single, permanent frame subscription (see CameraService).
    _frameSub = _camera.frameStream.listen(_onFrame);
  }

  // ─── State ────────────────────────────────────────────────────────────

  MeasurementState _state = MeasurementState.idle;
  MeasurementState get state => _state;

  String _statusMessage = 'Tap to start measurement';
  String get statusMessage => _statusMessage;

  // Capture buffers
  final List<double> _redBuffer = <double>[];
  final List<double> _greenBuffer = <double>[];
  final List<int> _timestampsNs = <int>[];

  /// Live red-channel samples. Treat as read-only.
  List<double> get redBuffer => _redBuffer;

  /// Live green-channel samples. Treat as read-only.
  List<double> get greenBuffer => _greenBuffer;

  // Timing
  DateTime? _captureStartTime;
  DateTime? _prepStart;
  double _elapsedSeconds = 0;
  double get elapsedSeconds => _elapsedSeconds;
  static const double captureDuration = 30.0; // seconds

  // Live finger detection
  bool _fingerDetected = false;
  bool get fingerDetected => _fingerDetected;
  int _fingerStreak = 0;

  // Live camera state
  bool _exposureLocked = false;
  bool get exposureLocked => _exposureLocked;

  double _clipRatio = 0;
  /// Fraction of clipped (blown-out) pixels in the ROI, 0–1.
  double get clipRatio => _clipRatio;

  int _droppedFrames = 0;
  /// Frames that arrived while the finger was not covering the lens.
  int get droppedFrames => _droppedFrames;

  // Latest frame values (for live waveform display)
  double _latestRed = 0;
  double _latestGreen = 0;
  double get latestRed => _latestRed;
  double get latestGreen => _latestGreen;

  /// Peak-to-peak swing of the green channel over the last ~2 s.
  /// Used by the UI to tell the user "the green trace is flat, ease the
  /// pressure" *before* wasting a 30 s recording.
  double get liveGreenSpan {
    final int n = _greenBuffer.length;
    if (n < 10) return 0;
    final int start = n > 60 ? n - 60 : 0;
    double lo = double.infinity;
    double hi = -double.infinity;
    for (int i = start; i < n; i++) {
      final double v = _greenBuffer[i];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    return hi - lo;
  }

  /// Same for red.
  double get liveRedSpan {
    final int n = _redBuffer.length;
    if (n < 10) return 0;
    final int start = n > 60 ? n - 60 : 0;
    double lo = double.infinity;
    double hi = -double.infinity;
    for (int i = start; i < n; i++) {
      final double v = _redBuffer[i];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    return hi - lo;
  }

  // Result
  MeasurementResult? _result;
  MeasurementResult? get result => _result;

  StreamSubscription? _frameSub;
  Timer? _timer;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  bool _finishing = false;

  // ─── Actions ──────────────────────────────────────────────────────────

  /// Start the measurement workflow.
  Future<void> startMeasurement() async {
    if (_state == MeasurementState.preparing ||
        _state == MeasurementState.capturing ||
        _state == MeasurementState.processing) {
      return; // already running — do not restart the camera
    }

    // Clean slate: this is what makes a second recording behave like a first.
    _result = null;
    _redBuffer.clear();
    _greenBuffer.clear();
    _timestampsNs.clear();
    _elapsedSeconds = 0;
    _fingerStreak = 0;
    _droppedFrames = 0;
    _clipRatio = 0;
    _exposureLocked = false;
    _finishing = false;
    _prepStart = DateTime.now();

    _state = MeasurementState.preparing;
    _statusMessage = 'Warming up the camera…';
    notifyListeners();

    final started = await _camera.startCapture();
    if (!started) {
      _state = MeasurementState.error;
      _statusMessage = 'Could not access camera. Check permissions.';
      notifyListeners();
    }
  }

  /// Cancel an in-progress measurement.
  Future<void> cancelMeasurement() async {
    _timer?.cancel();
    _timer = null;
    _finishing = true;
    await _camera.stopCapture();

    _state = MeasurementState.idle;
    _statusMessage = 'Measurement cancelled';
    _redBuffer.clear();
    _greenBuffer.clear();
    _timestampsNs.clear();
    _elapsedSeconds = 0;
    _finishing = false;
    notifyListeners();
  }

  /// Seconds spent waiting for the finger / camera to settle.
  double get prepSeconds => _prepStart == null
      ? 0
      : DateTime.now().difference(_prepStart!).inMilliseconds / 1000.0;

  /// Manual override: start recording even if the automatic finger detection
  /// does not trigger (different skin tone, thick callus, dirty lens…).
  void forceStart() {
    if (_state != MeasurementState.preparing) return;
    _beginCapture();
  }

  /// Process a frame from the native camera.
  void _onFrame(FrameColorData frame) {
    _latestRed = frame.redAvg;
    _latestGreen = frame.greenAvg;
    _fingerDetected = frame.isFingerDetected;
    _clipRatio = frame.clipRatio;
    _exposureLocked = frame.exposureLocked;

    if (_state == MeasurementState.preparing) {
      _fingerStreak = frame.isFingerDetected ? _fingerStreak + 1 : 0;

      final int warmupMs = _prepStart == null
          ? 0
          : DateTime.now().difference(_prepStart!).inMilliseconds;

      // Wait for the finger AND for auto-exposure / auto-white-balance to be
      // locked. Recording with AWB still hunting destroys the green channel.
      final bool ready =
          _fingerStreak >= 5 && (frame.exposureLocked || warmupMs > 3000);

      if (ready) {
        _beginCapture();
      } else {
        _statusMessage = frame.isFingerDetected
            ? 'Hold still — locking exposure…'
            : 'Rest your fingertip gently over camera + flash';
        _maybeNotify();
      }
      return;
    }

    if (_state == MeasurementState.capturing) {
      // Only store frames where the finger is actually on the lens. A lifted
      // finger injects a huge step into the series, which used to create a
      // strong low-frequency peak at ~40–45 BPM in the FFT.
      if (!frame.isFingerDetected) {
        _droppedFrames++;
        _statusMessage = '⚠ Keep your finger still — gap ignored';
        _maybeNotify();
        return;
      }

      _redBuffer.add(frame.redAvg);
      _greenBuffer.add(frame.greenAvg);
      _timestampsNs.add(frame.timestampNs);

      _statusMessage =
          'Recording… ${(captureDuration - _elapsedSeconds).toStringAsFixed(0)}s remaining';
      _maybeNotify();
    }
  }

  void _beginCapture() {
    _state = MeasurementState.capturing;
    _statusMessage = 'Recording pulse signal…';
    _captureStartTime = DateTime.now();
    _redBuffer.clear();
    _greenBuffer.clear();
    _timestampsNs.clear();
    _droppedFrames = 0;
    _elapsedSeconds = 0;

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_captureStartTime == null) return;
      _elapsedSeconds =
          DateTime.now().difference(_captureStartTime!).inMilliseconds / 1000.0;
      notifyListeners();

      if (_elapsedSeconds >= captureDuration && !_finishing) {
        _finishCapture();
      }
    });

    notifyListeners();
  }

  /// 30 seconds elapsed — stop camera and run DSP algorithms.
  Future<void> _finishCapture() async {
    if (_finishing) return;
    _finishing = true;

    _timer?.cancel();
    _timer = null;
    await _camera.stopCapture();

    final double duration = _elapsedSeconds;

    if (_redBuffer.length < 30) {
      _state = MeasurementState.error;
      _statusMessage = 'Not enough frames captured. Please try again.';
      _finishing = false;
      notifyListeners();
      return;
    }

    _state = MeasurementState.processing;
    _statusMessage = 'Analyzing pulse signal…';
    notifyListeners();

    // Let the "Analysing…" frame paint before the FFT blocks the isolate.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final profile = await _db.getUserProfile();

      final result = DspEngine.runFullPipeline(
        redSignal: _redBuffer.toList(growable: false),
        greenSignal: _greenBuffer.toList(growable: false),
        durationSeconds: duration,
        timestampsNs: _timestampsNs.toList(growable: false),
        weightKg: profile?.weightKg,
        heightCm: profile?.heightCm,
        age: profile?.age,
      );

      _result = result;

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
      _statusMessage = 'Analysis failed: $e';
    }
    _finishing = false;
    notifyListeners();
  }

  /// Reset to idle state (after viewing results).
  void reset() {
    _timer?.cancel();
    _timer = null;
    _state = MeasurementState.idle;
    _statusMessage = 'Tap to start measurement';
    _result = null;
    _redBuffer.clear();
    _greenBuffer.clear();
    _timestampsNs.clear();
    _elapsedSeconds = 0;
    _fingerStreak = 0;
    _droppedFrames = 0;
    _finishing = false;
    notifyListeners();
  }

  void _maybeNotify() {
    final DateTime now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds < 60) return;
    _lastNotify = now;
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
