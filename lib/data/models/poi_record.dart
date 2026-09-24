class PoiRecord {
  final String type; // 'peligro' | 'punto'
  final double lat;
  final double lng;
  final DateTime date;

  PoiRecord({
    required this.type,
    required this.lat,
    required this.lng,
    required this.date,
  });

  String get label => type == 'peligro' ? '⚠️ Peligro' : '📍 Punto guardado';

  /// Enlace de Google Maps — el formato más universal para compartir
  /// con alguien que no tenga esta app instalada.
  String get shareText =>
      '$label\nhttps://maps.google.com/?q=$lat,$lng';

  Map<String, dynamic> toJson() => {
        'type': type,
        'lat': lat,
        'lng': lng,
        'date': date.toIso8601String(),
      };

  factory PoiRecord.fromJson(Map<String, dynamic> j) => PoiRecord(
        type: j['type'],
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        date: DateTime.parse(j['date']),
      );
}
