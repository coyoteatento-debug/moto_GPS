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

  Map<String, dynamic> toJson() => {
    'destination': destination,
    'distanceKm': distanceKm,
    'durationMin': durationMin,
    'date': date.toIso8601String(),
    'routeCoords': routeCoords,
  };

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
