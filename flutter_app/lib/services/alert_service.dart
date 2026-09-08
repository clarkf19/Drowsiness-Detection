import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import 'drowsiness_pipeline.dart';
import 'settings_service.dart';

/// Manages high-priority audio alarms, haptic feedback, silent-mode bypass,
/// and the 15-second un-dismissed Emergency SOS escalation.
class AlertService extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final SettingsService? settingsService;

  bool _isDrowsyAlertActive = false;
  Timer? _sosTimer;
  int _sosCountdownSeconds = 15;
  bool _sosTriggered = false;

  VoidCallback? onEmergencySosTriggered;

  bool get isDrowsyAlertActive => _isDrowsyAlertActive;
  int get sosCountdownSeconds => _sosCountdownSeconds;
  bool get sosTriggered => _sosTriggered;

  AlertService({this.settingsService}) {
    _initAudioContext();
  }

  /// Configures AudioContext to bypass silent/do-not-disturb mode on Android
  Future<void> _initAudioContext() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm, // Bypasses silent mode
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.duckOthers,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('AlertService AudioContext initialization error: $e');
    }
  }

  /// Update alert state based on pipeline DrowsinessState.
  /// Both Low Vigilant and Drowsy states map to DrowsinessState.drowsy
  /// and trigger the same loud alarm at the configured volume.
  void updateAlertState(DrowsinessState state) {
    switch (state) {
      case DrowsinessState.drowsy:
        if (!_isDrowsyAlertActive) {
          triggerDrowsyAlarm();
        }
        break;

      case DrowsinessState.alert:
      case DrowsinessState.calibrating:
        if (_isDrowsyAlertActive) {
          dismissDrowsyAlert();
        }
        break;
    }
  }

  /// Triggers the loud looping alert sound + vibration pattern
  Future<void> triggerDrowsyAlarm() async {
    _isDrowsyAlertActive = true;
    _sosTriggered = false;
    _sosCountdownSeconds = 15;
    notifyListeners();

    final double volume = settingsService?.alarmVolume ?? 1.0;
    final bool vibrationEnabled = settingsService?.vibrationEnabled ?? true;

    try {
      // Configure volume and loop mode
      await _audioPlayer.setVolume(volume);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('sounds/alert_beep.wav'));

      // Repeating vibration pattern: 500ms vibrate, 500ms pause
      if (vibrationEnabled) {
        final hasVibe = await Vibration.hasVibrator();
        if (hasVibe == true) {
          Vibration.vibrate(pattern: [500, 500], repeat: 0);
        }
      }
    } catch (e) {
      debugPrint('AlertService error playing alarm sound/vibration: $e');
    }

    // Start 15-second Emergency SOS countdown
    _startSosCountdown();
  }

  /// 15-second countdown timer. If un-dismissed, escalates to SOS emergency notification.
  void _startSosCountdown() {
    _sosTimer?.cancel();
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isDrowsyAlertActive) {
        timer.cancel();
        return;
      }

      if (_sosCountdownSeconds > 0) {
        _sosCountdownSeconds--;
        notifyListeners();
      }

      if (_sosCountdownSeconds <= 0 && !_sosTriggered) {
        _sosTriggered = true;
        timer.cancel();
        debugPrint('EMERGENCY SOS: Drowsy alarm un-dismissed for >15 seconds!');
        onEmergencySosTriggered?.call();
        notifyListeners();
      }
    });
  }

  /// Dismisses active drowsy alert, stops looping audio, and stops vibration
  void dismissDrowsyAlert() {
    _isDrowsyAlertActive = false;
    _sosCountdownSeconds = 15;
    _sosTriggered = false;
    _sosTimer?.cancel();

    try {
      _audioPlayer.stop();
      Vibration.cancel();
    } catch (e) {
      debugPrint('AlertService error stopping audio/vibration: $e');
    }

    notifyListeners();
  }

  /// Test alarm audio at a specified volume (used in SettingsScreen)
  Future<void> playTestSound(double volume) async {
    try {
      await _audioPlayer.setVolume(volume.clamp(0.0, 1.0));
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(AssetSource('sounds/alert_beep.wav'));
    } catch (e) {
      debugPrint('AlertService playTestSound error: $e');
    }
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _audioPlayer.dispose();
    try {
      Vibration.cancel();
    } catch (_) {}
    super.dispose();
  }
}
