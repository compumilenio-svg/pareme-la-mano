import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'sfx.dart';

/// Música ambiental de fondo en volumen bajo (assets/music/).
class Ambient {
  static final ValueNotifier<bool> musicOn = ValueNotifier<bool>(true);
  static AudioPlayer? _p;
  static bool _wanted = false;
  static bool _listening = false;
  static String _name = '';
  static double _vol = 0.15;

  static Future<void> start(String name, {double volume = 0.15}) async {
    _name = name;
    _vol = volume;
    _wanted = true;
    if (!_listening) {
      _listening = true;
      Sfx.enabled.addListener(_apply);
      musicOn.addListener(_apply);
      try {
        // Que la música y los efectos suenen a la vez sin quitarse el audio.
        await AudioPlayer.global.setAudioContext(
            AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
                .build());
      } catch (_) {}
    }
    await _apply();
  }

  static Future<void> stop() async {
    _wanted = false;
    await _apply();
  }

  static Future<void> _apply() async {
    try {
      if (_wanted && Sfx.enabled.value && musicOn.value) {
        _p ??= AudioPlayer();
        await _p!.setReleaseMode(ReleaseMode.loop);
        await _p!.setVolume(_vol);
        if (_p!.state != PlayerState.playing) {
          await _p!.play(AssetSource('music/$_name.wav'));
        }
      } else if (_p != null) {
        await _p!.dispose();
        _p = null;
      }
    } catch (_) {}
  }
}

/// Botón para encender o apagar solo la música de fondo.
class MusicButton extends StatelessWidget {
  const MusicButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Ambient.musicOn,
      builder: (context, on, _) => IconButton(
        tooltip: on ? 'Quitar la música' : 'Poner la música',
        icon: Icon(on ? Icons.music_note : Icons.music_off),
        onPressed: () => Ambient.musicOn.value = !on,
      ),
    );
  }
}
