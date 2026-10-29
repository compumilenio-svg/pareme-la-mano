import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Efectos de sonido del juego (archivos en assets/sounds/).
class Sfx {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static Future<void> play(String name, {int delayMs = 0}) async {
    if (delayMs > 0) await Future<void>.delayed(Duration(milliseconds: delayMs));
    if (!enabled.value) return;
    AudioPlayer? p;
    Timer? safety;
    try {
      p = AudioPlayer();
      final player = p;
      // Siempre se libera el reproductor (evita acumular y retrasar el audio).
      player.onPlayerComplete.listen((_) => player.dispose());
      safety = Timer(const Duration(seconds: 12), () => player.dispose());
      await player.play(AssetSource('sounds/$name.wav'));
    } catch (_) {
      safety?.cancel();
      try {
        await p?.dispose();
      } catch (_) {}
    }
  }
}
