import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Efectos de sonido del juego (archivos en assets/sounds/).
class Sfx {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static Future<void> play(String name, {int delayMs = 0}) async {
    if (delayMs > 0) await Future<void>.delayed(Duration(milliseconds: delayMs));
    if (!enabled.value) return;
    try {
      final p = AudioPlayer();
      p.onPlayerComplete.listen((_) => p.dispose());
      await p.play(AssetSource('sounds/$name.wav'));
    } catch (_) {}
  }
}
