import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import '../music.dart';
import '../sfx.dart';

/// Ambiente de Batalla naval: sonar de fondo en bucle y, de vez en cuando,
/// mensajes de radio de onda corta en momentos al azar.
class RadarAmbience {
  static const int _clips = 9;
  static final Random _rng = Random();
  static Timer? _timer;
  static AudioPlayer? _radio;
  static int _last = -1;
  static bool _on = false;

  static void start() {
    if (_on) return;
    _on = true;
    Ambient.start('radar_sonar', volume: 0.25);
    _schedule(first: true);
  }

  static void stop() {
    _on = false;
    _timer?.cancel();
    _timer = null;
    final r = _radio;
    _radio = null;
    try {
      r?.dispose();
    } catch (_) {}
    Ambient.stop();
  }

  static void _schedule({bool first = false}) {
    _timer?.cancel();
    final secs = first ? 6 + _rng.nextInt(10) : 14 + _rng.nextInt(24);
    _timer = Timer(Duration(seconds: secs), () async {
      if (!_on) return;
      await _playClip();
      if (_on) _schedule();
    });
  }

  static Future<void> _playClip() async {
    if (!Sfx.enabled.value || !Ambient.musicOn.value) return;
    var i = _rng.nextInt(_clips) + 1;
    if (i == _last) i = i % _clips + 1;
    _last = i;
    try {
      final old = _radio;
      _radio = null;
      await old?.dispose();
      final p = AudioPlayer();
      _radio = p;
      p.onPlayerComplete.listen((_) {
        try {
          p.dispose();
        } catch (_) {}
        if (identical(_radio, p)) _radio = null;
      });
      await p.setVolume(0.5);
      await p.play(AssetSource('sounds/radio_$i.wav'));
    } catch (_) {}
  }
}
