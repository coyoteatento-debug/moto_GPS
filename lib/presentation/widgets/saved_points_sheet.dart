import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/poi_record.dart';

void showSavedPointsSheet(BuildContext context, List<PoiRecord> pois) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SavedPointsSheet(pois: pois),
  );
}

class _SavedPointsSheet extends StatelessWidget {
  final List<PoiRecord> pois;
  const _SavedPointsSheet({required this.pois});

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
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
          const Text('Puntos guardados por voz',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 16),
          Flexible(
            child: pois.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Di "GPS, marcar peligro" o "GPS, marcar punto"\nmientras manejas para guardarlos aquí.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: pois.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final poi = pois[i];
                      return ListTile(
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
