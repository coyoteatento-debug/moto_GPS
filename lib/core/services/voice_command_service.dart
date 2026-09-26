import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

enum VoiceCommandType { markDanger, savePoint, findGasStation }

class VoiceCommand {
  final VoiceCommandType type;
  final String rawText;
  const VoiceCommand(this.type, this.rawText);
}

/// Reconocimiento de voz continuo, EN EL DISPOSITIVO (offline), para
/// comandos cortos tipo "GPS, marcar peligro" — pensado para usarse con
/// el casco puesto y sin señal telefónica (sierra, zonas rurales, etc).
///
/// Nota realista: forzar `onDevice: true` requiere que el idioma tenga
/// el paquete de reconocimiento offline instalado en el teléfono
/// (Android lo gestiona en Ajustes > Voz > Reconocimiento offline).
/// Si no está instalado, el motor puede fallar silenciosamente — por
/// eso reintentamos solos ante error en vez de tronar la función.
class VoiceCommandService {
  static final VoiceCommandService _instance =
      VoiceCommandService._internal();
  factory VoiceCommandService() => _instance;
  VoiceCommandService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  bool _active = false;
  void Function(VoiceCommand)? _onCommand;
  void Function(bool listening)? _onListeningChange;

  bool get isActive => _active;

  String _localeId = 'es-MX';

  Future<bool> _ensureInit() async {
    if (_available) return true;
    _available = await _speech.initialize(
      onStatus: _onStatus,
      onError: (_) {
        // Ruido de casco / silencios largos producen error con frecuencia:
        // en vez de detener el modo, se reintenta solo.
        if (_active) _scheduleRestart();
      },
    );
    if (_available) {
      final locales = await _speech.locales();
      for (final preferred in ['es-MX', 'es-US', 'es-ES']) {
        if (locales.any((l) => l.localeId == preferred)) {
          _localeId = preferred;
          break;
        }
      }
    }
    return _available;
  }

  /// Activa el modo manos libres: escucha, procesa, y se reinicia solo
  /// en bucle hasta que se llame stop().
  Future<bool> start({
    required void Function(VoiceCommand) onCommand,
    void Function(bool listening)? onListeningChange,
  }) async {
    if (!await _ensureInit()) return false;
    _onCommand = onCommand;
    _onListeningChange = onListeningChange;
    _active = true;
    await _listenCycle();
    return true;
  }

  void stop() {
    _active = false;
    _speech.stop();
    _onListeningChange?.call(false);
  }

  void _onStatus(String status) {
    _onListeningChange?.call(status == 'listening');
    if (_active && (status == 'done' || status == 'notListening')) {
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (!_active) return;
    Future.delayed(const Duration(milliseconds: 500), _listenCycle);
  }

  Future<void> _listenCycle() async {
    if (!_active) return;
    await _speech.listen(
      onResult: _handleResult,
      localeId: _localeId,
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      partialResults: false, // solo frases completas: menos falsos positivos con ruido de casco
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
      onDevice: true, // ← fuerza reconocimiento local, sin datos móviles
      // Si tu versión resuelta de speech_to_text no acepta `onDevice`
      // como parámetro directo, cámbialo por:
      // listenOptions: SpeechListenOptions(onDevice: true, listenMode: ..., cancelOnError: true, partialResults: false),
    );
  }

  void _handleResult(SpeechRecognitionResult result) {
    if (!result.finalResult) return;
    final command = _parseCommand(result.recognizedWords);
    if (command != null) _onCommand?.call(command);
  }

  /// Reconoce comandos con la palabra de activación "gps" seguida de
  /// una acción. Tolerante a variaciones simples de la frase.
  VoiceCommand? _parseCommand(String text) {
    final normalized = _normalize(text);
    if (!normalized.contains('gps')) return null;

    if (_containsAny(normalized, ['peligro', 'precaucion', 'riesgo'])) {
      return VoiceCommand(VoiceCommandType.markDanger, text);
    }
    if (_containsAny(normalized, ['marcar punto', 'guardar punto', 'punto de interes'])) {
      return VoiceCommand(VoiceCommandType.savePoint, text);
    }
    if (_containsAny(normalized, ['gasolinera', 'gasolina', 'combustible'])) {
      return VoiceCommand(VoiceCommandType.findGasStation, text);
    }
    return null;
  }

  bool _containsAny(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  String _normalize(String text) {
    var t = text.toLowerCase();
    const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n'};
    accents.forEach((a, b) => t = t.replaceAll(a, b));
    return t;
  }

  void dispose() {
    _active = false;
    _speech.stop();
  }
}
