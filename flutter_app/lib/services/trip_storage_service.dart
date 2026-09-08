import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/trip_session.dart';

/// Service managing persistence of driving trip logs using Hive
class TripStorageService extends ChangeNotifier {
  static const String _boxName = 'trip_sessions';
  Box? _box;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    _isInitialized = true;
    notifyListeners();
  }

  /// Get all saved trip sessions, sorted with newest first
  List<TripSession> getAllTrips() {
    if (!_isInitialized || _box == null) return [];

    final List<TripSession> trips = [];
    for (final key in _box!.keys) {
      final rawData = _box!.get(key);
      if (rawData is Map) {
        try {
          trips.add(TripSession.fromMap(Map<dynamic, dynamic>.from(rawData)));
        } catch (e) {
          debugPrint('Error parsing trip session $key: $e');
        }
      }
    }

    // Sort descending by start time (newest first)
    trips.sort((a, b) => b.startTime.compareTo(a.startTime));
    return trips;
  }

  /// Save or update a trip session
  Future<void> saveTrip(TripSession session) async {
    if (!_isInitialized || _box == null) await init();
    await _box!.put(session.id, session.toMap());
    notifyListeners();
  }

  /// Delete a trip session by its unique ID
  Future<void> deleteTrip(String id) async {
    if (!_isInitialized || _box == null) return;
    await _box!.delete(id);
    notifyListeners();
  }

  /// Total count of saved trips
  int get totalTripsCount => _box?.length ?? 0;

  /// Clear all past trips
  Future<void> clearAll() async {
    if (!_isInitialized || _box == null) return;
    await _box!.clear();
    notifyListeners();
  }
}
