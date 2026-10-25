import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Mensaje rápido predefinido. Se usan textos fijos (no dictado libre) porque
/// son confiables con el ruido del casco y porque nunca contienen la palabra
/// de activación "GPS" (así un mensaje entrante no puede activar comandos).
class RideQuickMessage {
  final String id;
  final String label; // texto del botón
  final String text; // lo que se envía y se lee en voz alta
  final List<String> keywords; // para el comando de voz (sin acentos)
  const RideQuickMessage(this.id, this.label, this.text, this.keywords);
}

const List<RideQuickMessage> kRideQuickMessages = [
  RideQuickMessage('stop', 'Voy a parar', 'Voy a parar',
      ['parar', 'parada', 'me detengo']),
  RideQuickMessage('fuel', 'Necesito gasolina', 'Necesito gasolina',
      ['gasolina', 'combustible']),
  RideQuickMessage('wait', 'Esperen', 'Esperen por favor',
      ['esperen', 'espera', 'esperame']),
  RideQuickMessage('ok', 'Todo bien', 'Todo bien por aquí',
      ['todo bien', 'estoy bien']),
  RideQuickMessage('arrived', 'Ya llegué', 'Ya llegué',
      ['llegue', 'llegada']),
  RideQuickMessage('problem', 'Problema mecánico', 'Tengo un problema mecánico',
      ['problema', 'falla', 'averia']),
  RideQuickMessage('checkpoint', 'Retén adelante', 'Hay un retén adelante',
      ['reten', 'control', 'policia']),
  RideQuickMessage('behind', 'Voy atrás', 'Me quedé atrás, esperen',
      ['atras', 'me quede']),
];

/// Texto del aviso automático cuando alguien marca un peligro en rodada.
const String kRideDangerText = 'Peligro adelante';

class RideChatMessage {
  final String key;
  final String uid;
  final String username;
  final String text;
  final String kind; // 'quick' | 'danger'
  final int ts; // milisegundos (hora del servidor)

  const RideChatMessage({
    required this.key,
    required this.uid,
    required this.username,
    required this.text,
    required this.kind,
    required this.ts,
  });

  bool get isDanger => kind == 'danger';

  /// Un mensaje de hace más de 90 s ya no sirve (p. ej. se envió sin señal
  /// y llegó mucho después): se ignora en vez de leerlo fuera de contexto.
  bool get isStale =>
      ts > 0 && DateTime.now().millisecondsSinceEpoch - ts > 90000;

  factory RideChatMessage.fromMap(String key, Map<String, dynamic> m) =>
      RideChatMessage(
        key: key,
        uid: m['uid']?.toString() ?? '',
        username: m['username']?.toString() ?? 'Amigo',
        text: m['text']?.toString() ?? '',
        kind: m['kind']?.toString() ?? 'quick',
        ts: (m['ts'] as num?)?.toInt() ?? 0,
      );
}

enum RideChatSendResult { sent, tooFast, failed }

/// Mensajes de voz del modo rodada (versión de mensajes rápidos).
/// Se guardan en Realtime Database en groupRideMessages/{rideId}/{id}.
class RideChatService {
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  DateTime? _lastSentAt;

  Future<RideChatSendResult> send(
    String rideId,
    String username,
    String text, {
    String kind = 'quick',
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return RideChatSendResult.failed;

    // Un mensaje cada 3 s como máximo (evita spam o comandos repetidos)
    final now = DateTime.now();
    if (_lastSentAt != null &&
        now.difference(_lastSentAt!) < const Duration(seconds: 3)) {
      return RideChatSendResult.tooFast;
    }
    _lastSentAt = now;

    try {
      await _rtdb.ref('groupRideMessages/$rideId').push().set({
        'uid': uid,
        'username': username,
        'text': text,
        'kind': kind,
        'ts': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 6));
      return RideChatSendResult.sent;
    } catch (_) {
      return RideChatSendResult.failed;
    }
  }

  /// Mensajes NUEVOS de la rodada (no reproduce el historial al unirse).
  Stream<RideChatMessage> watchMessages(String rideId) async* {
    final ref = _rtdb.ref('groupRideMessages/$rideId');

    // Claves que ya existían al conectarse: se ignoran.
    final seen = <String>{};
    try {
      final initial = await ref.get();
      final value = initial.value;
      if (value is Map) seen.addAll(value.keys.map((k) => k.toString()));
    } catch (_) {}

    await for (final event in ref.onChildAdded) {
      final key = event.snapshot.key;
      final value = event.snapshot.value;
      if (key == null || value is! Map || seen.contains(key)) continue;
      seen.add(key);
      final msg =
          RideChatMessage.fromMap(key, Map<String, dynamic>.from(value));
      if (msg.isStale || msg.text.isEmpty) continue;
      yield msg;
    }
  }
}
