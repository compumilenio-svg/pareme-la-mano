import 'package:flutter_tts/flutter_tts.dart';

/// Voz del bot cantor (texto a voz del celular, en español).
class BingoVoice {
  static final FlutterTts _tts = FlutterTts();
  static bool _ready = false;

  static Future<void> _init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('es-MX');
      await _tts.setSpeechRate(0.42);
      await _tts.setPitch(1.0);
    } catch (_) {}
    _ready = true;
  }

  static Future<void> say(String text) async {
    try {
      await _init();
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
