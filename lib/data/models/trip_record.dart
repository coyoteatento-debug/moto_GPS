class TripRecord {
  final String destination;
  final double distanceKm;
  final int durationMin;
  final DateTime date;
  final List<List<double>> routeCoords;

  TripRecord({
    required this.destination,
    required this.distanceKm,
    required this.durationMin,
    required this.date,
    this.routeCoords = const [],
  });

  Map<String, dynamic> toJson() {
  final coords = _sampleCoords(routeCoords, maxPoints: 100);
  return {
    'destination': destination,
    'distanceKm':  distanceKm,
    'durationMin': durationMin,
    'date':        date.toIso8601String(),
    'routeCoords': coords,
  };
}

Map<String, dynamic> toJsonCompact() {
    final coords = _sampleCoords(routeCoords, maxPoints: 50); // ← mitad de puntos
    return {
      'destination': destination,
      'distanceKm':  distanceKm,
      'durationMin': durationMin,
      'date':        date.toIso8601String(),
      'routeCoords': coords,
    };
  }
  
List<List<double>> _sampleCoords(
    List<List<double>> coords, {required int maxPoints}) {
  if (coords.length <= maxPoints) return coords;
  final step   = (coords.length - 1) / (maxPoints - 1);
  final result = <List<double>>[];
  for (int i = 0; i < maxPoints; i++) {
    result.add(coords[(i * step).round()]);
  }
  return result;
}

  factory TripRecord.fromJson(Map<String, dynamic> j) => TripRecord(
    destination: j['destination'],
    distanceKm: (j['distanceKm'] as num).toDouble(),
    durationMin: j['durationMin'],
    date: DateTime.parse(j['date']),
    routeCoords: (j['routeCoords'] as List? ?? [])
        .map((c) => (c as List).map((v) => (v as num).toDouble()).toList())
        .toList(),
  );
}
