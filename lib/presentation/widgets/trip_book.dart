import 'package:flutter/material.dart';
import '../../data/models/trip_record.dart';
import 'route_painter.dart';

class TripBook extends StatelessWidget {
  final List<TripRecord> trips;

  const TripBook({super.key, required this.trips});

  void _showTripRoute(BuildContext context, TripRecord trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trip.destination,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _tripStat(Icons.straighten, '${trip.distanceKm} km', Colors.blue),
                  const SizedBox(width: 20),
                  _tripStat(Icons.timer_outlined, '${trip.durationMin} min', Colors.orange),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: trip.routeCoords.length >= 2
                    ? Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F0E8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CustomPaint(
                            painter: RoutePainter(trip.routeCoords),
                            size: Size.infinite,
                          ),
                        ),
                      )
                    : const Center(
                        child: Text('Sin datos de ruta',
                            style: TextStyle(color: Colors.grey)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tripStat(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
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
              itemBuilder: (_, i) {
                final trip = trips[i];
                final dateStr =
                    '${trip.date.day.toString().padLeft(2, '0')}/'
                    '${trip.date.month.toString().padLeft(2, '0')}/'
                    '${trip.date.year}  '
                    '${trip.date.hour.toString().padLeft(2, '0')}:'
                    '${trip.date.minute.toString().padLeft(2, '0')}';
                return GestureDetector(
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
                              _tripStat(Icons.straighten, '${trip.distanceKm} km', Colors.blue),
                              const SizedBox(width: 20),
                              _tripStat(Icons.timer_outlined, '${trip.durationMin} min', Colors.orange),
                              const Spacer(),
                              Text(dateStr,
                                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
