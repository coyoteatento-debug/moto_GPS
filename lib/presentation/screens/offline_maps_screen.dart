import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../di/providers.dart';
import '../controllers/map_controller.dart';

class OfflineMapsScreen extends ConsumerStatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  ConsumerState<OfflineMapsScreen> createState() =>
      _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends ConsumerState<OfflineMapsScreen> {
  final _nameController = TextEditingController();
  List<Map<String, String>> _regions = [];
  bool _downloading = false;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    final prefs = ref.read(prefsSourceProvider);
    final regions = await prefs.loadOfflineRegions();
    if (mounted) setState(() => _regions = regions);
  }

  Future<void> _download() async {
    final position = ref.read(mapControllerProvider).currentPosition;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esperando ubicación GPS...')),
      );
      return;
    }
    final name = _nameController.text.trim().isEmpty
        ? 'Mi zona ${_regions.length + 1}'
        : _nameController.text.trim();
    final id = 'region_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _downloading = true;
      _progress = 0.0;
    });

    try {
      final service = ref.read(offlineMapServiceProvider);
      await service.downloadRegion(
        regionId: id,
        lat: position.latitude,
        lng: position.longitude,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      final prefs = ref.read(prefsSourceProvider);
      final updated = [..._regions, {'id': id, 'name': name}];
      await prefs.saveOfflineRegions(updated);
      if (mounted) {
        setState(() {
          _regions = updated;
          _downloading = false;
          _nameController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al descargar: $e')),
        );
      }
    }
  }

  Future<void> _delete(Map<String, String> region) async {
    final service = ref.read(offlineMapServiceProvider);
    await service.deleteRegion(region['id']!);
    final prefs = ref.read(prefsSourceProvider);
    final updated =
        _regions.where((r) => r['id'] != region['id']).toList();
    await prefs.saveOfflineRegions(updated);
    if (mounted) setState(() => _regions = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Mapas sin conexión'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Descarga el mapa de ~50km alrededor de tu ubicación actual '
              'para poder navegar sin señal. Solo cubre el modo día.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              enabled: !_downloading,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nombre de la zona (ej. Durango)',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue)),
              ),
            ),
            const SizedBox(height: 12),
            if (_downloading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: _downloading ? null : _download,
              icon: const Icon(Icons.download),
              label: Text(
                  _downloading ? 'Descargando...' : 'Descargar zona actual'),
            ),
            const SizedBox(height: 24),
            const Text('Zonas descargadas',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _regions.isEmpty
                  ? const Center(
                      child: Text('Aún no descargas ninguna zona',
                          style: TextStyle(color: Colors.white38)),
                    )
                  : ListView.builder(
                      itemCount: _regions.length,
                      itemBuilder: (_, i) {
                        final region = _regions[i];
                        return ListTile(
                          leading:
                              const Icon(Icons.map, color: Colors.blue),
                          title: Text(region['name'] ?? 'Zona',
                              style: const TextStyle(color: Colors.white)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                            onPressed: () => _delete(region),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
