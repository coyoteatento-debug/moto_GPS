import 'package:flutter/material.dart';
import '../../data/models/trip_record.dart';

class TripBook extends StatelessWidget {
  final List<TripRecord> trips;

  const TripBook({super.key, required this.trips});

  void _showTripRoute(BuildContext context, TripRecord trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // Destino
            Row(children: [
              const Icon(Icons.location_on, color: Colors.red, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trip.destination,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 24),
            // Tarjetas de estadísticas
            Row(children: [
              _statCard(Icons.straighten,
                  '${trip.distanceKm} km', 'Distancia', Colors.blue),
              const SizedBox(width: 12),
              _statCard(Icons.timer_outlined,
                  '${trip.durationMin} min', 'Duración', Colors.orange),
              const SizedBox(width: 12),
              _statCard(Icons.calendar_today_outlined,
                  _formatDate(trip.date), 'Fecha', Colors.teal),
            ]),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(
                color: Colors.grey,
                fontSize: 11)),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
           '${date.month.toString().padLeft(2, '0')}/'
           '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('📒 Libro de viaje'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: trips.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('🏍️', style: TextStyle(fontSize: 52)),
                  SizedBox(height: 12),
                  Text('Aún no tienes viajes',
                      style: TextStyle(fontSize: 17, color: Colors.grey)),
                  SizedBox(height: 6),
                  Text(
                    'Completa una navegación para verlos aquí',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: trips.length,
              cacheExtent: 500,                    // ← AGREGADO
              addRepaintBoundaries: true,           // ← AGREGADO
              itemBuilder: (_, i) {
                final trip = trips[i];
                return RepaintBoundary(
                  child: GestureDetector(
                    onTap: () => _showTripRoute(context, trip),
                    child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.red, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  trip.destination,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 15),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.straighten, color: Colors.blue, size: 16),
                              const SizedBox(width: 4),
                              Text('${trip.distanceKm} km',
                                  style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(width: 16),
                              Icon(Icons.timer_outlined, color: Colors.orange, size: 16),
                              const SizedBox(width: 4),
                              Text('${trip.durationMin} min',
                                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 13)),
                              const Spacer(),
                              Text(_formatDate(trip.date),
                                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }
}
