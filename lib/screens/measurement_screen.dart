/// Measurement Screen — Live 30-second PPG capture
///
/// Shows:
/// - Finger placement guide with live detection feedback
/// - Real-time PPG oscilloscope waveform (Red & Green channels)
/// - 30-second radial countdown timer
/// - Live status messages
///
/// On completion, navigates to the Results screen.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/measurement_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/ppg_wave_painter.dart';
import 'results_screen.dart';

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen>
    with TickerProviderStateMixin {
  late AnimationController _ringPulseController;
  late AnimationController _breatheController;

  MeasurementProvider? _provider;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _ringPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Auto-start measurement. Navigation happens from a listener (one time),
    // NEVER from build() — doing it in build pushed the results route again on
    // every rebuild, which is what produced the "slideshow" on a 2nd run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<MeasurementProvider>();
      _provider = p;
      p.addListener(_onProviderChanged);
      p.startMeasurement();
    });
  }

  void _onProviderChanged() {
    final p = _provider;
    if (p == null || _navigated || !mounted) return;
    if (p.state != MeasurementState.complete || p.result == null) return;

    _navigated = true;
    final result = p.result!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ResultsScreen(result: result)),
      );
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    // Release the 30 s buffers so the next recording starts from a clean slate.
    final p = _provider;
    if (p != null) {
      Future<void>.microtask(p.reset);
    }
    _ringPulseController.dispose();
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MeasurementProvider>(
      builder: (context, provider, _) {
        return PopScope(
          canPop: provider.state == MeasurementState.idle ||
              provider.state == MeasurementState.error,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _showCancelDialog(context, provider);
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: const Text('Measuring'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _showCancelDialog(context, provider),
              ),
              actions: [
                // A/B switch for the camera capture-request tuning.
                // Applies to the NEXT recording (settings are applied at bind).
                IconButton(
                  tooltip: provider.cameraTuning
                      ? 'Camera tuning ON (tap to disable)'
                      : 'Camera tuning OFF (tap to enable)',
                  icon: Icon(
                    Icons.tune,
                    color: provider.cameraTuning
                        ? AppColors.accentBlue
                        : AppColors.textTertiary,
                  ),
                  onPressed: () {
                    provider.toggleCameraTuning();
                    final bool on = provider.cameraTuning;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(on
                            ? 'Camera tuning ON — next recording only'
                            : 'Camera tuning OFF — next recording only'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 1),

                    // ─── Finger Detection Ring ───────────────────
                    _buildFingerRing(provider),
                    const SizedBox(height: 32),

                    // ─── Status Message ──────────────────────────
                    Text(
                      provider.statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: provider.fingerDetected
                            ? AppColors.pulseGreen
                            : AppColors.accentOrange,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getSubMessage(provider),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),

                    const Spacer(flex: 1),

                    // ─── Live PPG Waveforms ──────────────────────
                    if (provider.state == MeasurementState.capturing) ...[
                      PpgWaveformWidget(
                        data: provider.redBuffer,
                        color: AppColors.heartRed,
                        label: 'RED CHANNEL',
                        height: 90,
                      ),
                      const SizedBox(height: 10),
                      PpgWaveformWidget(
                        data: provider.greenBuffer,
                        color: AppColors.pulseGreen,
                        label: 'GREEN CHANNEL',
                        height: 90,
                      ),
                      const SizedBox(height: 16),

                      // Frame counter
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildInfoChip(
                            Icons.videocam,
                            '${provider.redBuffer.length} frames',
                          ),
                          const SizedBox(width: 16),
                          _buildInfoChip(
                            Icons.speed,
                            '${(provider.redBuffer.length / math.max(provider.elapsedSeconds, 0.1)).toStringAsFixed(1)} FPS',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ─── Live signal-quality hints ───────────────
                      _buildQualityHints(provider),
                    ],

                    if (provider.state == MeasurementState.preparing &&
                        provider.prepSeconds > 6) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: provider.forceStart,
                        child: const Text(
                          'Finger not detected? Start anyway',
                          style: TextStyle(
                            color: AppColors.accentBlue,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],

                    if (provider.state == MeasurementState.processing) ...[
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(
                        color: AppColors.accentPurple,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Running FFT analysis...',
                        style: TextStyle(
                          color: AppColors.accentPurple,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],

                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFingerRing(MeasurementProvider provider) {
    final bool isCapturing = provider.state == MeasurementState.capturing;
    final double progress =
        isCapturing ? provider.elapsedSeconds / MeasurementProvider.captureDuration : 0;
    final bool detected = provider.fingerDetected;

    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          SizedBox(
            width: 180,
            height: 180,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 6,
              color: AppColors.surfaceBorder,
              backgroundColor: Colors.transparent,
            ),
          ),

          // Progress ring (during capture)
          if (isCapturing)
            SizedBox(
              width: 180,
              height: 180,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 6,
                color: AppColors.accentBlue,
                backgroundColor: Colors.transparent,
                strokeCap: StrokeCap.round,
              ),
            ),

          // Pulsing glow ring
          AnimatedBuilder(
            animation: _ringPulseController,
            builder: (context, child) {
              return Container(
                width: 140 + (_ringPulseController.value * 8),
                height: 140 + (_ringPulseController.value * 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (detected ? AppColors.pulseGreen : AppColors.accentOrange)
                        .withOpacity(0.3 - _ringPulseController.value * 0.2),
                    width: 3,
                  ),
                ),
              );
            },
          ),

          // Inner circle
          AnimatedBuilder(
            animation: _breatheController,
            builder: (context, child) {
              final scale = 1.0 + _breatheController.value * 0.03;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: detected
                          ? [
                              AppColors.pulseGreen.withOpacity(0.2),
                              AppColors.pulseGreen.withOpacity(0.05),
                            ]
                          : [
                              AppColors.accentOrange.withOpacity(0.15),
                              AppColors.accentOrange.withOpacity(0.03),
                            ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isCapturing) ...[
                        Text(
                          '${(MeasurementProvider.captureDuration - provider.elapsedSeconds).ceil()}',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'seconds',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ] else ...[
                        Icon(
                          detected
                              ? Icons.fingerprint
                              : Icons.touch_app_outlined,
                          color: detected
                              ? AppColors.pulseGreen
                              : AppColors.accentOrange,
                          size: 48,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Live hints that tell the user what the camera is actually seeing.
  /// They never change the numbers — they only explain a bad capture.
  Widget _buildQualityHints(MeasurementProvider provider) {
    final double greenSpan = provider.liveGreenSpan;
    final double clip = provider.clipRatio;

    final bool flat = provider.greenBuffer.length > 90 && greenSpan < 1.0;
    final bool clipping = clip > 0.02;

    final List<Widget> chips = [
      _buildInfoChip(
        Icons.show_chart,
        'GREEN AC ${greenSpan.toStringAsFixed(1)}',
      ),
      const SizedBox(width: 12),
      _buildInfoChip(
        Icons.wb_sunny_outlined,
        'CLIP ${(clip * 100).toStringAsFixed(0)}%',
      ),
    ];

    String? hint;
    if (clipping) {
      hint = 'Too much light — lift the finger 1 mm so the image is not '
          'blown out, then hold it still.';
    } else if (flat) {
      hint = 'Green trace is flat — you are pressing too hard. Ease the '
          'pressure until the green line starts to move.';
    }

    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: chips),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.accentOrange,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  String _getSubMessage(MeasurementProvider provider) {
    switch (provider.state) {
      case MeasurementState.preparing:
        return 'Rest your index fingertip LIGHTLY over the rear camera lens\n'
            'and the LED flash. Cover the lens fully, do not press hard —\n'
            'pressing squeezes the capillaries shut and flattens the pulse.';
      case MeasurementState.capturing:
        return 'Recording PPG signal • Keep still • Light contact only';
      case MeasurementState.processing:
        return 'Computing dual-channel FFT & blood pressure';
      case MeasurementState.error:
        return 'Something went wrong. Try again.';
      default:
        return '';
    }
  }

  void _showCancelDialog(BuildContext context, MeasurementProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Measurement?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'The current recording will be discarded.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: () {
              provider.cancelMeasurement();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );
  }
}
