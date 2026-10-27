/// Results Screen — Displays analysis results after a 30-second measurement
///
/// Shows:
/// - Heart rate (FFT dual-channel) with confidence score
/// - Blood pressure (systolic / diastolic) with AHA classification
/// - Algorithm comparison: FFT vs Sliding Average (paper demonstration)
/// - Intermediate values: ET, BSA, SV, PP (for academic presentation)
/// - FFT spectrum visualization
/// - Journal note input

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/app_database.dart';
import '../services/dsp_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/vitals_card.dart';
import '../widgets/ppg_wave_painter.dart';

class ResultsScreen extends StatefulWidget {
  final MeasurementResult result;

  const ResultsScreen({super.key, required this.result});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  final TextEditingController _notesController = TextEditingController();
  bool _showAlgorithmComparison = false;
  bool _showIntermediateValues = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final fft = r.fftResult;
    final bp = r.bpResult;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => _saveAndClose(context),
          ),
        ],
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _entranceController,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // ─── Heart Rate Hero Card ────────────────────
                _buildHeroCard(fft),
                const SizedBox(height: 16),

                // ─── Blood Pressure ──────────────────────────
                if (bp != null) ...[
                  _buildBpSection(bp),
                  const SizedBox(height: 16),
                ],

                // ─── FFT Spectrum Visualization ──────────────
                _buildSpectrumSection(fft),
                const SizedBox(height: 16),

                // ─── Algorithm Comparison Toggle ─────────────
                _buildAlgorithmComparison(r),
                const SizedBox(height: 16),

                // ─── Intermediate Values (for academic defense) ──
                if (bp != null) _buildIntermediateValues(bp, fft),
                const SizedBox(height: 16),

                // ─── Measurement Metadata ────────────────────
                _buildMetadataSection(r),
                const SizedBox(height: 16),

                // ─── Journal Notes ───────────────────────────
                _buildNotesSection(),
                const SizedBox(height: 32),

                // ─── Done Button ─────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveAndClose(context),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Save & Return'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.accentGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(FftResult fft) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: AppColors.heartGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.heartRed.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.favorite, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          Text(
            fft.heartRate.round().toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'BPM',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  fft.confidence > 0.9
                      ? Icons.verified
                      : Icons.info_outline,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Dual-FFT Confidence: ${(fft.confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Red: ${fft.bpmRed.toStringAsFixed(1)} BPM  •  Green: ${fft.bpmGreen.toStringAsFixed(1)} BPM',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBpSection(BloodPressureResult bp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(text: 'BLOOD PRESSURE'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: VitalsCard(
                icon: Icons.arrow_upward,
                label: 'Systolic',
                value: bp.systolic.round().toString(),
                unit: 'mmHg',
                accentColor: AppColors.bpBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VitalsCard(
                icon: Icons.arrow_downward,
                label: 'Diastolic',
                value: bp.diastolic.round().toString(),
                unit: 'mmHg',
                accentColor: AppColors.accentCyan,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // AHA Stage badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(bp.stageColor).withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Color(bp.stageColor).withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(bp.stageColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bp.stage,
                      style: TextStyle(
                        color: Color(bp.stageColor),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${bp.systolic.round()}/${bp.diastolic.round()} mmHg  •  PP: ${bp.pulsePressure.toStringAsFixed(1)} mmHg',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpectrumSection(FftResult fft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(text: 'FFT POWER SPECTRUM'),
        const SizedBox(height: 8),
        if (fft.spectrumRed.isNotEmpty)
          PpgWaveformWidget(
            data: fft.spectrumRed.take(100).toList(),
            color: AppColors.heartRed,
            label: 'RED SPECTRUM',
            height: 70,
          ),
        const SizedBox(height: 8),
        if (fft.spectrumGreen.isNotEmpty)
          PpgWaveformWidget(
            data: fft.spectrumGreen.take(100).toList(),
            color: AppColors.pulseGreen,
            label: 'GREEN SPECTRUM',
            height: 70,
          ),
      ],
    );
  }

  Widget _buildAlgorithmComparison(MeasurementResult r) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              _showAlgorithmComparison = !_showAlgorithmComparison;
            }),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.compare_arrows,
                      color: AppColors.accentPurple, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Algorithm Comparison (Paper Demo)',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _showAlgorithmComparison
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_showAlgorithmComparison) ...[
            const Divider(color: AppColors.surfaceBorder, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _ComparisonRow(
                    label: 'Algorithm 2 (FFT)',
                    value: '${r.fftResult.heartRate.round()} BPM',
                    detail: 'Dual-channel frequency-domain analysis',
                    color: AppColors.pulseGreen,
                    icon: Icons.check_circle,
                  ),
                  const SizedBox(height: 12),
                  _ComparisonRow(
                    label: 'Algorithm 1 (Sliding Avg)',
                    value: '${r.slidingResult.heartRate.round()} BPM',
                    detail:
                        '4-frame rolling average, ${r.slidingResult.peakCount} peaks detected',
                    color: AppColors.accentOrange,
                    icon: Icons.warning_amber,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'The paper found Algorithm 1 had ~60% error due to '
                      'cardiac double-peak (dicrotic wave) miscounting. '
                      'Algorithm 2 uses FFT to find the fundamental frequency, '
                      'eliminating waveform morphology issues.',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIntermediateValues(BloodPressureResult bp, FftResult fft) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              _showIntermediateValues = !_showIntermediateValues;
            }),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.biotech, color: AppColors.accentCyan, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Hemodynamic Intermediate Values',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _showIntermediateValues
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_showIntermediateValues) ...[
            const Divider(color: AppColors.surfaceBorder, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _ValueRow(
                    formula: 'ET = 364.5 − 1.23 × HR',
                    label: 'Ejection Time',
                    value: '${bp.ejectionTime.toStringAsFixed(1)} ms',
                  ),
                  _ValueRow(
                    formula: 'BSA = 0.007184 × W^0.425 × H^0.725',
                    label: 'Body Surface Area',
                    value: '${bp.bodySurfaceArea.toStringAsFixed(3)} m²',
                  ),
                  _ValueRow(
                    formula: 'SV = −6.6 + 0.25(ET−35) − 0.62×HR + 40.4×BSA − 0.51×Age',
                    label: 'Stroke Volume',
                    value: '${bp.strokeVolume.toStringAsFixed(1)} mL',
                  ),
                  _ValueRow(
                    formula: 'PP = SV / (0.013W − 0.007Age − 0.004HR + 1.307)',
                    label: 'Pulse Pressure',
                    value: '${bp.pulsePressure.toStringAsFixed(1)} mmHg',
                  ),
                  _ValueRow(
                    formula: 'SBP = 83.25 + ⅔ × PP',
                    label: 'Systolic BP',
                    value: '${bp.systolic.toStringAsFixed(1)} mmHg',
                  ),
                  _ValueRow(
                    formula: 'DBP = 83.25 − ⅓ × PP',
                    label: 'Diastolic BP',
                    value: '${bp.diastolic.toStringAsFixed(1)} mmHg',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Peak freq Red: ${fft.peakFreqRed.toStringAsFixed(3)} Hz  •  '
                        'Green: ${fft.peakFreqGreen.toStringAsFixed(3)} Hz',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetadataSection(MeasurementResult r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MetaItem(
              label: 'Duration', value: '${r.durationSeconds.toStringAsFixed(1)}s'),
          _MetaItem(label: 'Frames', value: '${r.totalFrames}'),
          _MetaItem(label: 'FPS', value: r.effectiveFps.toStringAsFixed(1)),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(text: 'JOURNAL NOTES'),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'e.g. "After jogging", "Resting", "Morning coffee"',
            hintStyle: const TextStyle(color: AppColors.textTertiary),
          ),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        ),
      ],
    );
  }

  void _saveAndClose(BuildContext context) {
    // If notes were entered, update the latest measurement
    if (_notesController.text.isNotEmpty) {
      final db = Provider.of<AppDatabase>(context, listen: false);
      db.getAllMeasurements().then((list) {
        if (list.isNotEmpty) {
          db.updateMeasurementNotes(list.first.id, _notesController.text);
        }
      });
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper Widgets
// ═══════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final Color color;
  final IconData icon;

  const _ComparisonRow({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(detail,
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String formula;
  final String label;
  final String value;

  const _ValueRow({
    required this.formula,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              Text(value,
                  style: const TextStyle(
                      color: AppColors.accentCyan,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          Text(formula,
              style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontStyle: FontStyle.italic)),
          const Divider(color: AppColors.surfaceBorder, height: 12),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final String label;
  final String value;
  const _MetaItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style:
                const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
      ],
    );
  }
}
