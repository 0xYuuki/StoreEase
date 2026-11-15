import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class AudioService {
  static AudioPlayer? _player;

  /// Plays a distinct retail POS scanner beep sound, haptic vibration, and system click.
  static Future<void> playScanBeep() async {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}

    try {
      _player ??= AudioPlayer();
      await _player?.stop();
      await _player?.play(AssetSource('beep.wav'), mode: PlayerMode.lowLatency);
    } catch (_) {}
  }

  static void dispose() {
    try {
      _player?.dispose();
      _player = null;
    } catch (_) {}
  }
}
