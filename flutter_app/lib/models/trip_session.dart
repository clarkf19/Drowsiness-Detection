import 'dart:convert';

/// Represents a single time-sampled point during the driving session for charting
class VigilancePoint {
  final int secondOffset; // Seconds since session started
  final double vigilanceScore; // 0.0 to 100.0
  final bool isDrowsy; // True if model predicted Drowsy (or Low Vigilant)

  const VigilancePoint({
    required this.secondOffset,
    required this.vigilanceScore,
    required this.isDrowsy,
  });

  Map<String, dynamic> toMap() {
    return {
      'secondOffset': secondOffset,
      'vigilanceScore': vigilanceScore,
      'isDrowsy': isDrowsy,
    };
  }

  factory VigilancePoint.fromMap(Map<dynamic, dynamic> map) {
    return VigilancePoint(
      secondOffset: (map['secondOffset'] as num?)?.toInt() ?? 0,
      vigilanceScore: (map['vigilanceScore'] as num?)?.toDouble() ?? 100.0,
      isDrowsy: (map['isDrowsy'] as bool?) ?? false,
    );
  }
}

/// Represents a completed driving trip session saved to local Hive storage
class TripSession {
  final String id;
  final DateTime startTime;
  final int durationSeconds;
  final int drowsyEventsCount;
  final double averageVigilance;
  final List<VigilancePoint> timeline;

  const TripSession({
    required this.id,
    required this.startTime,
    required this.durationSeconds,
    required this.drowsyEventsCount,
    required this.averageVigilance,
    required this.timeline,
  });

  /// Formatted duration string, e.g. "00:24:15"
  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Letter safety rating based on vigilance score and drowsy incidents
  String get safetyRating {
    if (drowsyEventsCount == 0 && averageVigilance >= 85) return 'A+';
    if (drowsyEventsCount <= 1 && averageVigilance >= 75) return 'A';
    if (drowsyEventsCount <= 3 && averageVigilance >= 60) return 'B';
    if (drowsyEventsCount <= 5 && averageVigilance >= 50) return 'C';
    return 'D';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'durationSeconds': durationSeconds,
      'drowsyEventsCount': drowsyEventsCount,
      'averageVigilance': averageVigilance,
      'timeline': timeline.map((p) => p.toMap()).toList(),
    };
  }

  factory TripSession.fromMap(Map<dynamic, dynamic> map) {
    final rawTimeline = map['timeline'] as List<dynamic>? ?? [];
    return TripSession(
      id: map['id']?.toString() ?? '',
      startTime: DateTime.tryParse(map['startTime']?.toString() ?? '') ?? DateTime.now(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      drowsyEventsCount: (map['drowsyEventsCount'] as num?)?.toInt() ?? 0,
      averageVigilance: (map['averageVigilance'] as num?)?.toDouble() ?? 100.0,
      timeline: rawTimeline
          .map((item) => VigilancePoint.fromMap(item as Map<dynamic, dynamic>))
          .toList(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory TripSession.fromJson(String source) =>
      TripSession.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
