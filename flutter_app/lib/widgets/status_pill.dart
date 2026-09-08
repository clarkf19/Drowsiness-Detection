import 'package:flutter/material.dart';
import '../services/drowsiness_pipeline.dart';

/// Animated status pill header badge displaying CALIBRATING, ALERT, or DROWSY state
class StatusPill extends StatelessWidget {
  final DrowsinessState state;

  const StatusPill({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    IconData icon;

    switch (state) {
      case DrowsinessState.calibrating:
        color = const Color(0xFF38BDF8); // Electric blue
        text = 'CALIBRATING';
        icon = Icons.sync_rounded;
        break;
      case DrowsinessState.alert:
        color = const Color(0xFF10B981); // Emerald green
        text = 'ALERT';
        icon = Icons.check_circle_rounded;
        break;
      case DrowsinessState.drowsy:
        color = const Color(0xFFEF4444); // Crimson red
        text = 'DROWSY';
        icon = Icons.warning_rounded;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 14,
            spreadRadius: 1,
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
