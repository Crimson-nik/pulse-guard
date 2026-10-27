/// History Screen — Paginated measurement log with journal entries
///
/// Displays all past measurements from the Drift database,
/// grouped by date, with heart rate, BP, and notes.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context, listen: false);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'History',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: StreamBuilder<List<Measurement>>(
                      stream: db.watchAllMeasurements(),
                      builder: (context, snap) {
                        final count = snap.data?.length ?? 0;
                        return Text(
                          '$count readings',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Measurement list
            Expanded(
              child: StreamBuilder<List<Measurement>>(
                stream: db.watchAllMeasurements(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.accentBlue),
                    );
                  }

                  final items = snapshot.data!;
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history,
                              color: AppColors.textTertiary, size: 56),
                          const SizedBox(height: 12),
                          const Text(
                            'No measurements yet',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final m = items[index];
                      return _HistoryCard(
                        measurement: m,
                        onDelete: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              title: const Text('Delete Reading?',
                                  style: TextStyle(
                                      color: AppColors.textPrimary)),
                              content: const Text(
                                'This measurement will be permanently deleted.',
                                style:
                                    TextStyle(color: AppColors.textSecondary),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete',
                                      style: TextStyle(
                                          color: AppColors.accentRed)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            db.deleteMeasurement(m.id);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Measurement measurement;
  final VoidCallback onDelete;

  const _HistoryCard({required this.measurement, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final m = measurement;
    final dateStr = DateFormat('EEE, MMM d').format(m.timestamp);
    final timeStr = DateFormat('h:mm a').format(m.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date / time + delete
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 13, color: AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Text(
                    '$dateStr  •  $timeStr',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.delete_outline,
                    size: 18, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Metrics row
          Row(
            children: [
              // Heart Rate
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.heartRed.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.favorite,
                          color: AppColors.heartRed, size: 14),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m.heartRateFft.round()}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text('BPM',
                            style: TextStyle(
                                color: AppColors.textTertiary, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),

              // Blood Pressure
              if (m.systolic != null && m.diastolic != null)
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.bpBlue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.speed,
                            color: AppColors.bpBlue, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m.systolic!.round()}/${m.diastolic!.round()}',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text('mmHg',
                              style: TextStyle(
                                  color: AppColors.textTertiary, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),

              // Confidence
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: m.confidence > 0.9
                      ? AppColors.accentGreen.withOpacity(0.1)
                      : AppColors.accentOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(m.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: m.confidence > 0.9
                        ? AppColors.accentGreen
                        : AppColors.accentOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          // Notes
          if (m.notes != null && m.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      color: AppColors.textTertiary, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.notes!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // BP Stage badge
          if (m.bpStage != null) ...[
            const SizedBox(height: 8),
            Text(
              m.bpStage!,
              style: TextStyle(
                color: AppColors.accentCyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
