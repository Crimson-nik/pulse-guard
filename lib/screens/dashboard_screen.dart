/// Dashboard Screen — Home page with latest vitals and quick actions
///
/// Shows the most recent measurement, 7-day trend sparklines,
/// and a prominent button to start a new 30-second measurement.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../theme/app_theme.dart';
import '../widgets/vitals_card.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onStartMeasurement;

  const DashboardScreen({
    super.key,
    required this.onStartMeasurement,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context, listen: false);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PulseGuard',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'PPG Heart Rate & Blood Pressure',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: const Icon(
                      Icons.science_outlined,
                      color: AppColors.accentPurple,
                      size: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Start Measurement Card
              _buildStartCard(),
              const SizedBox(height: 24),

              // Latest Results
              const Text(
                'LATEST RESULTS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),

              // Stream latest measurement from database
              StreamBuilder<List<Measurement>>(
                stream: db.watchAllMeasurements(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyState();
                  }

                  final latest = snapshot.data!.first;
                  return _buildLatestResults(latest);
                },
              ),

              const SizedBox(height: 24),

              // Algorithm Info Banner
              _buildAlgorithmBanner(),

              const SizedBox(height: 100), // Bottom nav padding
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartCard() {
    return GestureDetector(
      onTap: widget.onStartMeasurement,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final double scale = 1.0 + (_pulseController.value * 0.015);
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667EEA).withOpacity(0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Start 30s Check',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Place finger on camera + flash',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          Icon(
            Icons.monitor_heart_outlined,
            color: AppColors.textTertiary,
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'No measurements yet',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the button above to take your first reading',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLatestResults(Measurement m) {
    final timeStr = DateFormat('MMM d, h:mm a').format(m.timestamp);

    return Column(
      children: [
        // Heart Rate card
        VitalsCard(
          icon: Icons.favorite,
          label: 'Heart Rate (FFT)',
          value: m.heartRateFft.round().toString(),
          unit: 'BPM',
          accentColor: AppColors.heartRed,
          subtitle: 'Confidence: ${(m.confidence * 100).toStringAsFixed(0)}%',
        ),
        const SizedBox(height: 12),

        // Blood Pressure cards (side by side)
        if (m.systolic != null && m.diastolic != null)
          Row(
            children: [
              Expanded(
                child: VitalsCard(
                  icon: Icons.arrow_upward,
                  label: 'Systolic',
                  value: m.systolic!.round().toString(),
                  unit: 'mmHg',
                  accentColor: AppColors.bpBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: VitalsCard(
                  icon: Icons.arrow_downward,
                  label: 'Diastolic',
                  value: m.diastolic!.round().toString(),
                  unit: 'mmHg',
                  accentColor: AppColors.accentCyan,
                ),
              ),
            ],
          ),

        if (m.bpStage != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppColors.textTertiary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Status: ${m.bpStage}  •  $timeStr',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Algorithm comparison row
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'FFT METHOD',
                value: m.heartRateFft.round().toString(),
                unit: 'BPM',
                color: AppColors.pulseGreen,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                label: 'SLIDING AVG',
                value: m.heartRateSliding.round().toString(),
                unit: 'BPM',
                color: AppColors.accentOrange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlgorithmBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_graph, color: AppColors.accentPurple, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Journal Algorithm',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Dual-channel FFT (Red + Green) with Hamming windowing.\n'
            'Based on Sharma et al., Computers & Electrical Engineering, 2022.\n'
            'Blood pressure via Chandrasekaran hemodynamic model.',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
