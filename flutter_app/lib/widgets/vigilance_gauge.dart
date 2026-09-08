import 'dart:math';
import 'package:flutter/material.dart';

/// Real-time circular arc gauge displaying 0–100% driver vigilance.
/// Transitions dynamically from Emerald Green (>=70%) to Crimson Red (<70%).
class VigilanceGauge extends StatelessWidget {
  final double score; // 0.0 to 100.0
  final double size;
  final bool isCalibrating;

  const VigilanceGauge({
    super.key,
    required this.score,
    this.size = 180,
    this.isCalibrating = false,
  });

  Color _getColorForScore(double val) {
    if (isCalibrating) return const Color(0xFF38BDF8); // Sky blue
    if (val >= 70.0) return const Color(0xFF10B981); // Emerald green
    if (val >= 40.0) return const Color(0xFFF59E0B); // Amber warning
    return const Color(0xFFEF4444); // Crimson red
  }

  String _getLabelForScore(double val) {
    if (isCalibrating) return 'CALIBRATING';
    if (val >= 70.0) return 'ALERT';
    if (val >= 40.0) return 'WARNING';
    return 'DROWSY';
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: isCalibrating ? 50 : score.clamp(0.0, 100.0)),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, animatedScore, child) {
        final color = _getColorForScore(animatedScore);
        final label = _getLabelForScore(animatedScore);

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1E293B).withValues(alpha: 0.75), // Glass dark slate
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ],
            border: Border.all(
              color: color.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Custom Circular Gauge Painter
              CustomPaint(
                size: Size(size, size),
                painter: _GaugePainter(
                  percent: animatedScore / 100.0,
                  activeColor: color,
                  trackColor: Colors.white10,
                ),
              ),

              // Central Readout
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isCalibrating ? '--' : '${animatedScore.toInt()}%',
                    style: TextStyle(
                      fontSize: size * 0.22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: size * 0.075,
                        fontWeight: FontWeight.bold,
                        color: color,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percent;
  final Color activeColor;
  final Color trackColor;

  _GaugePainter({
    required this.percent,
    required this.activeColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 14;
    const strokeWidth = 10.0;

    const startAngle = 135 * (pi / 180); // Bottom left
    const sweepAngle = 270 * (pi / 180); // 270 degree arc

    // Background track arc
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Active progress arc
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressSweep = sweepAngle * percent.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      progressSweep,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trackColor != trackColor;
  }
}
