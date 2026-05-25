import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  String _lastSpoken = '';

  bool _ttsAvailable = false;                      // ← AGREGADO

  Future<void> init() async {
    try {
      await _tts.setLanguage('es-MX');
      await _tts.setSpeechRate(0.52);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _lastSpoken = '';
      });
      _ttsAvailable = true;                        // ← AGREGADO
    } catch (_) {
      try {
        await _tts.setLanguage('es');
        _tts.setCompletionHandler(() {             // ← AGREGADO
          _isSpeaking = false;
          _lastSpoken = '';
        });
        _ttsAvailable = true;
      } catch (_) {
        _ttsAvailable = false;
      }
    }
  }

  Timer? _safetyTimer;                              // ← AGREGADO

  Future<void> speak(String text) async {
    if (!_ttsAvailable) return;
    if (text.isEmpty) return;
    if (_isSpeaking) return;
    if (text == _lastSpoken) return;
    _isSpeaking = true;
    _lastSpoken = text;
    _safetyTimer?.cancel();                         // ← AGREGADO
    _safetyTimer = Timer(                           // ← AGREGADO
      const Duration(seconds: 15),
      () {
        _isSpeaking = false;
        _lastSpoken = '';
      },
    );
    try {
      await _tts.speak(text);
    } catch (_) {
      _isSpeaking = false;
      _lastSpoken = '';
      _safetyTimer?.cancel();                       // ← AGREGADO
    }
  }

  Future<void> stop() async {
    _safetyTimer?.cancel();
    _isSpeaking = false;       // ← agrega esta línea
    _lastSpoken = '';
    await _tts.stop();
  }
}
