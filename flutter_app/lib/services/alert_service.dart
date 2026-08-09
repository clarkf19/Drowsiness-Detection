import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'drowsiness_pipeline.dart';

/// Points 24 & 25: Audio alerts, vibration patterns, silent mode bypass, and escalation
class AlertService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _lowVigilantTimer;
  int _lowVigilantSeconds = 0;
  bool _isDrowsyAlertActive = false;

  bool get isDrowsyAlertActive => _isDrowsyAlertActive;

  AlertService() {
    _initAudioContext();
  }

  /// Point 30: Configure AudioContext to bypass silent mode on Android
  Future<void> _initAudioContext() async {
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSelfNoise: false,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: DarwinAudioContext(
          category: DarwinAudioCategory.playback,
          options: [
            DarwinAudioContextOptions.mixWithOthers,
            DarwinAudioContextOptions.duckOthers,
          ],
        ),
      ),
    );
  }

  /// Update alerts based on current DrowsinessState
  void updateAlertState(DrowsinessState state, {required Function onEscalateToDrowsy}) {
    switch (state) {
      case DrowsinessState.drowsy:
        _stopLowVigilantTimer();
        if (!_isDrowsyAlertActive) {
          triggerDrowsyAlarm();
        }
        break;

      case DrowsinessState.lowVigilant:
        if (!_isDrowsyAlertActive) {
          _triggerLowVigilantWarning(onEscalateToDrowsy);
        }
        break;

      case DrowsinessState.alert:
        dismissDrowsyAlert();
        _stopLowVigilantTimer();
        break;
    }
  }

  /// Point 24: Trigger loud beeping alarm sound + repeating vibration pattern
  Future<void> triggerDrowsyAlarm() async {
    _isDrowsyAlertActive = true;

    try {
      // Play loud alarm beep on repeat
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('sounds/alert_beep.mp3'));

      // Repeat vibration pattern: 500ms vibrate, 500ms pause
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [500, 500], repeat: 0);
      }
    } catch (e) {
      print('AlertService error playing alarm: $e');
    }
  }

  /// Point 25: Trigger soft chime sound for Low Vigilant state
  Future<void> _triggerLowVigilantWarning(Function onEscalateToDrowsy) async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(AssetSource('sounds/low_vigilant_chime.mp3'));
    } catch (e) {
      print('AlertService error playing chime: $e');
    }

    // Start 60-second escalation timer
    _lowVigilantSeconds = 0;
    _lowVigilantTimer?.cancel();
    _lowVigilantTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _lowVigilantSeconds++;
      if (_lowVigilantSeconds >= 60) {
        timer.cancel();
        print('Low Vigilant persisted for 60s -> Escalating to Drowsy alarm!');
        triggerDrowsyAlarm();
        onEscalateToDrowsy();
      }
    });
  }

  /// Dismiss active drowsy alert and stop sound/vibration
  void dismissDrowsyAlert() {
    _isDrowsyAlertActive = false;
    _audioPlayer.stop();
    Vibration.cancel();
  }

  void _stopLowVigilantTimer() {
    _lowVigilantTimer?.cancel();
    _lowVigilantSeconds = 0;
  }

  void dispose() {
    _audioPlayer.dispose();
    _stopLowVigilantTimer();
    Vibration.cancel();
  }
}
