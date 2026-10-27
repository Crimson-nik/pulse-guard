/// PPG Waveform Painter — Real-time oscilloscope-style pulse wave
///
/// Renders a scrolling, smooth bezier-interpolated waveform of the
/// live PPG signal (Red or Green channel) during the 30-second capture.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PpgWavePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final Color glowColor;
  final double strokeWidth;
  final int maxPoints;

  PpgWavePainter({
    required this.data,
    this.lineColor = const Color(0xFF00E676),
    Color? glowColor,
    this.strokeWidth = 2.5,
    this.maxPoints = 200,
  }) : glowColor = glowColor ?? lineColor.withOpacity(0.3);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    // Only show the last `maxPoints` samples
    final int start = math.max(0, data.length - maxPoints);
    final List<double> visible = data.sublist(start);

    if (visible.length < 2) return;

    // Auto-scale Y axis
    double minVal = visible.reduce(math.min);
    double maxVal = visible.reduce(math.max);
    double range = maxVal - minVal;
    if (range < 1) range = 1;

    // Padding
    const double topPad = 8;
    const double bottomPad = 8;
    final double plotHeight = size.height - topPad - bottomPad;
    // Scale to the samples we actually have, so a short buffer still fills the
    // width instead of being squeezed into the left edge.
    final double dx =
        visible.length > 1 ? size.width / (visible.length - 1) : size.width;

    // Build path
    final Path path = Path();
    final Path fillPath = Path();

    for (int i = 0; i < visible.length; i++) {
      final double x = i * dx;
      final double normalizedY = (visible[i] - minVal) / range;
      final double y = topPad + plotHeight * (1.0 - normalizedY);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        // Smooth bezier interpolation between points
        final double prevX = (i - 1) * dx;
        final double prevNY = (visible[i - 1] - minVal) / range;
        final double prevY = topPad + plotHeight * (1.0 - prevNY);
        final double cpx = (prevX + x) / 2;
        path.cubicTo(cpx, prevY, cpx, y, x, y);
        fillPath.cubicTo(cpx, prevY, cpx, y, x, y);
      }
    }

    // Fill gradient under the curve
    fillPath.lineTo((visible.length - 1) * dx, size.height);
    fillPath.close();

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          lineColor.withOpacity(0.15),
          lineColor.withOpacity(0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Glow effect
    final Paint glowPaint = Paint()
      ..color = glowColor
      ..strokeWidth = strokeWidth + 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawPath(path, glowPaint);

    // Main line
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    // Pulsing dot at the end
    if (visible.isNotEmpty) {
      final double lastX = (visible.length - 1) * dx;
      final double lastNY = (visible.last - minVal) / range;
      final double lastY = topPad + plotHeight * (1.0 - lastNY);

      // Outer glow
      canvas.drawCircle(
        Offset(lastX, lastY),
        6,
        Paint()
          ..color = lineColor.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Inner dot
      canvas.drawCircle(
        Offset(lastX, lastY),
        3.5,
        Paint()..color = lineColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PpgWavePainter oldDelegate) {
    return data.length != oldDelegate.data.length ||
        (data.isNotEmpty &&
            oldDelegate.data.isNotEmpty &&
            data.last != oldDelegate.data.last);
  }
}

/// Widget wrapper for the PPG waveform painter.
class PpgWaveformWidget extends StatelessWidget {
  final List<double> data;
  final Color color;
  final double height;
  final String? label;
  final int maxPoints;

  const PpgWaveformWidget({
    super.key,
    required this.data,
    this.color = AppColors.pulseGreen,
    this.height = 120,
    this.label,
    this.maxPoints = 200,
  });

  @override
  Widget build(BuildContext context) {
    // Snapshot the last `maxPoints` samples. The provider hands us its live
    // buffer (same List instance every frame), and the painter compares
    // old/new data to decide whether to repaint — comparing a list with
    // itself would never repaint, so we pass a copy.
    final int start = data.length > maxPoints ? data.length - maxPoints : 0;
    final List<double> snapshot = data.sublist(start);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              label!,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
        Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: PpgWavePainter(
              data: snapshot,
              lineColor: color,
              maxPoints: maxPoints,
            ),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }
}
