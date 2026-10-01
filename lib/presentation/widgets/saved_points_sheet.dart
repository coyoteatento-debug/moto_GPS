import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/poi_record.dart';
import '../../data/models/saved_place.dart';

void showSavedPointsSheet(
  BuildContext context,
  List<PoiRecord> pois,
  List<SavedPlaceRecord> places,
  ValueChanged<SavedPlaceRecord> onGoToPlace,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SavedPointsSheet(
      pois: pois,
      places: places,
      onGoToPlace: onGoToPlace,
    ),
  );
}

class _SavedPointsSheet extends StatelessWidget {
  final List<PoiRecord> pois;
  final List<SavedPlaceRecord> places;
  final ValueChanged<SavedPlaceRecord> onGoToPlace;
  const _SavedPointsSheet({
    required this.pois,
    required this.places,
    required this.onGoToPlace,
  });

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text('Lugares favoritos',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 8),
                if (places.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Toca el mapa, confirma un destino y usa\n"Guardar como favorito" para verlo aquí.\nLuego di "GPS, llévame a [nombre]".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...places.map((p) => ListTile(
                        leading: const Icon(Icons.star, color: Colors.amber),
                        title: Text(p.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(_formatDate(p.date)),
                        trailing: IconButton(
                          icon: const Icon(Icons.navigation, color: Colors.blue),
                          onPressed: () {
                            Navigator.pop(context);
                            onGoToPlace(p);
                          },
                        ),
                      )),
                const Divider(height: 32),
                const Text('Puntos guardados por voz',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 8),
                if (pois.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Di "GPS, marcar peligro" o "GPS, marcar lugar"\nmientras manejas para guardarlos aquí.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...pois.map((poi) => ListTile(
                        leading: Text(
                          poi.type == 'peligro' ? '⚠️' : '📍',
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(poi.label,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(_formatDate(poi.date)),
                        trailing: IconButton(
                          icon: const Icon(Icons.share, color: Colors.blue),
                          onPressed: () => Share.share(poi.shareText),
                        ),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
