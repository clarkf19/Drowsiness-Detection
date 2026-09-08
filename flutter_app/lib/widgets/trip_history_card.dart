import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trip_session.dart';

/// Card displaying past trip summary on the start screen
class TripHistoryCard extends StatelessWidget {
  final TripSession session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const TripHistoryCard({
    super.key,
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  Color _getRatingColor(String rating) {
    switch (rating) {
      case 'A+':
      case 'A':
        return const Color(0xFF10B981); // Emerald green
      case 'B':
        return const Color(0xFF38BDF8); // Blue
      case 'C':
        return const Color(0xFFF59E0B); // Amber
      default:
        return const Color(0xFFEF4444); // Red
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratingColor = _getRatingColor(session.safetyRating);
    final formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(session.startTime);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Date & Rating Badge & Delete button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.drive_eta_rounded, color: Colors.white60, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: ratingColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ratingColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            'Grade ${session.safetyRating}',
                            style: TextStyle(
                              color: ratingColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                  ],
                ),

                const Divider(color: Colors.white10, height: 20),

                // Bottom row: Duration, Incidents, Average Vigilance
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Duration
                    _buildStatItem(
                      label: 'DURATION',
                      value: session.formattedDuration,
                      icon: Icons.timer_outlined,
                      color: Colors.white,
                    ),

                    // Drowsy Incidents
                    _buildStatItem(
                      label: 'DROWSY ALERTS',
                      value: '${session.drowsyEventsCount}',
                      icon: Icons.warning_amber_rounded,
                      color: session.drowsyEventsCount == 0
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),

                    // Avg Vigilance
                    _buildStatItem(
                      label: 'AVG VIGILANCE',
                      value: '${session.averageVigilance.toInt()}%',
                      icon: Icons.speed_rounded,
                      color: session.averageVigilance >= 70
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color.withValues(alpha: 0.8)),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
