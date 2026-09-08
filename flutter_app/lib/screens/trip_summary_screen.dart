import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/trip_session.dart';
import '../services/trip_storage_service.dart';
import '../widgets/metric_card.dart';

/// Screen displayed at the end of a driving session or when reviewing a trip from history.
/// Features trip metrics and an interactive fl_chart vigilance timeline.
class TripSummaryScreen extends StatelessWidget {
  final TripSession session;

  const TripSummaryScreen({super.key, required this.session});

  Color _getRatingColor(String rating) {
    switch (rating) {
      case 'A+':
      case 'A':
        return const Color(0xFF10B981);
      case 'B':
        return const Color(0xFF38BDF8);
      case 'C':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratingColor = _getRatingColor(session.safetyRating);
    final formattedDate = DateFormat('EEEE, MMM d, yyyy • h:mm a').format(session.startTime);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          'Trip Summary',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Delete Trip Log?', style: TextStyle(color: Colors.white)),
                  content: const Text(
                    'This driving session will be permanently removed.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                await context.read<TripStorageService>().deleteTrip(session.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          // Header: Date & Safety Grade Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ratingColor.withValues(alpha: 0.25),
                  const Color(0xFF1E293B),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ratingColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formattedDate,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      session.safetyRating.startsWith('A')
                          ? 'Excellent Driver Vigilance'
                          : session.safetyRating == 'B'
                              ? 'Good Driving Vigilance'
                              : 'Caution: Drowsiness Detected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: ratingColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ratingColor, width: 2),
                  ),
                  child: Text(
                    session.safetyRating,
                    style: TextStyle(
                      color: ratingColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2x2 Grid of Key Metrics
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Duration',
                  value: session.formattedDuration,
                  icon: Icons.timer_outlined,
                  accentColor: const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Drowsy Alerts',
                  value: '${session.drowsyEventsCount}',
                  icon: Icons.warning_amber_rounded,
                  accentColor: session.drowsyEventsCount == 0
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Avg Vigilance',
                  value: '${session.averageVigilance.toInt()}%',
                  icon: Icons.speed_rounded,
                  accentColor: session.averageVigilance >= 70
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Safety Policy',
                  value: 'Unified',
                  icon: Icons.shield_rounded,
                  accentColor: const Color(0xFFA855F7), // Purple
                  subtitle: 'Immediate Drowsy Trigger',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Interactive fl_chart Timeline Graph
          _buildChartSection(),

          const SizedBox(height: 32),

          // Done Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    final spots = <FlSpot>[];

    if (session.timeline.isNotEmpty) {
      for (final pt in session.timeline) {
        spots.add(FlSpot(pt.secondOffset.toDouble(), pt.vigilanceScore));
      }
    } else {
      // Fallback points for preview
      spots.add(const FlSpot(0, 95));
      spots.add(FlSpot(session.durationSeconds.toDouble(), session.averageVigilance));
    }

    final maxX = (spots.last.x > 0) ? spots.last.x : 60.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'VIGILANCE TIMELINE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
              ),
              Row(
                children: [
                  _buildLegendItem(color: const Color(0xFF10B981), text: 'Alert (>=70%)'),
                  const SizedBox(width: 12),
                  _buildLegendItem(color: const Color(0xFFEF4444), text: 'Drowsy (<70%)'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                minX: 0,
                maxX: maxX,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (val) => FlLine(
                    color: Colors.white10,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 25,
                      reservedSize: 36,
                      getTitlesWidget: (val, meta) => Text(
                        '${val.toInt()}%',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (maxX / 4).clamp(1.0, double.infinity),
                      getTitlesWidget: (val, meta) {
                        final mins = (val / 60).floor();
                        final secs = (val % 60).toInt();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            mins > 0 ? '${mins}m' : '${secs}s',
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: const Color(0xFF38BDF8),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF38BDF8).withValues(alpha: 0.35),
                          const Color(0xFF38BDF8).withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String text}) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}
