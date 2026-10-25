import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';

/// Prioridad de un mensaje de voz (mayor índice = más importante).
///  - low:    mensajes informativos (p. ej. mensajes del grupo)
///  - normal: confirmaciones y alertas
///  - high:   indicaciones de giro (nunca deben perderse)
enum TtsPriority { low, normal, high }

class _Utterance {
  final String text;
  final TtsPriority priority;
  final DateTime enqueuedAt = DateTime.now();

  final Duration? maxAgeOverride;
  final double pitch;

  _Utterance(this.text, this.priority, {this.maxAgeOverride, this.pitch = 1.0});

  /// Tiempo máximo que un mensaje puede esperar en cola. Pasado ese
  /// tiempo ya no sirve (un "gira a la derecha" tardío confunde).
  Duration get maxAge {
    if (maxAgeOverride != null) return maxAgeOverride!;
    switch (priority) {
      case TtsPriority.high:
        return const Duration(seconds: 12);
      case TtsPriority.normal:
        return const Duration(seconds: 8);
      case TtsPriority.low:
        return const Duration(seconds: 6);
    }
  }

  bool get isStale => DateTime.now().difference(enqueuedAt) > maxAge;
}

class TtsService {
  static const int _maxQueue = 6;

  final FlutterTts _tts = FlutterTts();
  final List<_Utterance> _queue = [];
  _Utterance? _current;
  Timer? _safetyTimer;
  bool _ttsAvailable = false;

  Future<void> init() async {
    try {
      await _tts.setLanguage('es-MX');
      await _tts.setSpeechRate(0.52);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(_onFinished);
      _ttsAvailable = true;
    } catch (_) {
      try {
        await _tts.setLanguage('es');
        _tts.setCompletionHandler(_onFinished);
        _ttsAvailable = true;
      } catch (_) {
        _ttsAvailable = false;
      }
    }
  }

  /// Encola un mensaje de voz.
  ///  - Los mensajes no se descartan por estar ocupada la voz: esperan
  ///    su turno, ordenados por prioridad.
  ///  - Un mensaje de mayor prioridad interrumpe a uno de menor prioridad.
  ///  - Si el mismo texto ya se está diciendo o ya está en cola, se ignora.
  Future<void> speak(
    String text, {
    TtsPriority priority = TtsPriority.normal,
    Duration? maxAge, // sobrescribe cuánto puede esperar en cola
    double pitch = 1.0, // tono de voz (más grave = distinto a las indicaciones)
  }) async {
    if (!_ttsAvailable) return;
    final clean = text.trim();
    if (clean.isEmpty) return;

    if (_current?.text == clean) return;
    if (_queue.any((u) => u.text == clean)) return;

    final utterance =
        _Utterance(clean, priority, maxAgeOverride: maxAge, pitch: pitch);

    // Insertar por prioridad (FIFO dentro de la misma prioridad)
    final insertAt =
        _queue.indexWhere((u) => u.priority.index < priority.index);
    if (insertAt == -1) {
      _queue.add(utterance);
    } else {
      _queue.insert(insertAt, utterance);
    }

    // Límite de cola: se descarta lo menos importante / más reciente
    while (_queue.length > _maxQueue) {
      _queue.removeLast();
    }

    // Un aviso más importante interrumpe a uno menos importante
    final current = _current;
    if (current != null &&
        priority.index > current.priority.index &&
        _queue.contains(utterance)) {
      await _interruptCurrent();
    }
    _processQueue();
  }

  Future<void> _interruptCurrent() async {
    _safetyTimer?.cancel();
    _current = null;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> _processQueue() async {
    if (_current != null) return;

    _queue.removeWhere((u) => u.isStale);
    if (_queue.isEmpty) return;

    final next = _queue.removeAt(0);
    _current = next;

    // Respaldo por si el motor de voz nunca avisa que terminó
    _safetyTimer?.cancel();
    _safetyTimer = Timer(_safetyDuration(next.text), _onFinished);

    try {
      await _tts.setPitch(next.pitch);
    } catch (_) {}

    try {
      await _tts.speak(next.text);
    } catch (_) {
      _onFinished();
    }
  }

  void _onFinished() {
    _safetyTimer?.cancel();
    _current = null;
    _processQueue();
  }

  Duration _safetyDuration(String text) =>
      Duration(milliseconds: min(20000, 3000 + text.length * 120));

  Future<void> stop() async {
    _safetyTimer?.cancel();
    _safetyTimer = null;
    _queue.clear();
    _current = null;
    await _tts.stop();
  }
}
