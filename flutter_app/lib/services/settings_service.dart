import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages user settings and preferences persisted via SharedPreferences
class SettingsService extends ChangeNotifier {
  static const String _keyAlarmVolume = 'setting_alarm_volume';
  static const String _keyVibrationEnabled = 'setting_vibration_enabled';
  static const String _keySmoothingWindow = 'setting_smoothing_window';
  static const String _keyEmergencyContact = 'setting_emergency_contact';

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  // Defaults
  double _alarmVolume = 1.0; // Full volume
  bool _vibrationEnabled = true;
  int _smoothingWindow = 3; // Temporal smoothing window (2 to 5)
  String _emergencyContact = '';

  bool get isInitialized => _isInitialized;
  double get alarmVolume => _alarmVolume;
  bool get vibrationEnabled => _vibrationEnabled;
  int get smoothingWindow => _smoothingWindow;
  String get emergencyContact => _emergencyContact;

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();

    _alarmVolume = _prefs.getDouble(_keyAlarmVolume) ?? 1.0;
    _vibrationEnabled = _prefs.getBool(_keyVibrationEnabled) ?? true;
    _smoothingWindow = _prefs.getInt(_keySmoothingWindow) ?? 3;
    _emergencyContact = _prefs.getString(_keyEmergencyContact) ?? '';

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setAlarmVolume(double volume) async {
    _alarmVolume = volume.clamp(0.0, 1.0);
    await _prefs.setDouble(_keyAlarmVolume, _alarmVolume);
    notifyListeners();
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    _vibrationEnabled = enabled;
    await _prefs.setBool(_keyVibrationEnabled, _vibrationEnabled);
    notifyListeners();
  }

  Future<void> setSmoothingWindow(int windowSize) async {
    _smoothingWindow = windowSize.clamp(2, 5);
    await _prefs.setInt(_keySmoothingWindow, _smoothingWindow);
    notifyListeners();
  }

  Future<void> setEmergencyContact(String contact) async {
    _emergencyContact = contact.trim();
    await _prefs.setString(_keyEmergencyContact, _emergencyContact);
    notifyListeners();
  }
}
