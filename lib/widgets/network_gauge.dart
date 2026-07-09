import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/constants.dart';

/// Circular gauge showing network strength %, color-banded per spec:
/// 80-100 Excellent (green), 50-79 Good (green/yellow), 20-49 Weak (orange),
/// 0-19 Very Weak (red).
class NetworkGauge extends StatelessWidget {
  final int percent;
  final double size;

  const NetworkGauge({super.key, required this.percent, this.size = 220});

  Color get _color {
    if (percent >= 80) return AppColors.statusGood;
    if (percent >= 50) return AppColors.statusGood;
    if (percent >= 20) return AppColors.statusWeak;
    return AppColors.statusBad;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(percent: percent.clamp(0, 100), color: _color),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: size * 0.18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _bandLabel,
                style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: size * 0.07),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _bandLabel {
    if (percent >= 80) return 'Excellent';
    if (percent >= 50) return 'Good';
    if (percent >= 20) return 'Weak';
    return 'Very Weak';
  }
}

class _GaugePainter extends CustomPainter {
  final int percent;
  final Color color;

  _GaugePainter({required this.percent, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * (percent / 100);

    final trackPaint = Paint()
      ..color = AppColors.card
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.color != color;
}
