class SavedPlaceRecord {
  final String name;
  final double lat;
  final double lng;
  final DateTime date;

  SavedPlaceRecord({
    required this.name,
    required this.lat,
    required this.lng,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lng': lng,
        'date': date.toIso8601String(),
      };

  factory SavedPlaceRecord.fromJson(Map<String, dynamic> json) =>
      SavedPlaceRecord(
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        date: DateTime.parse(json['date'] as String),
      );
}
