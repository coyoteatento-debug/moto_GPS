import 'dart:math' as math;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Descarga tiles + estilo de una zona (~50km alrededor de un punto)
/// para uso sin conexión, usando OfflineManager/TileStore de Mapbox.
class OfflineMapService {
  OfflineManager? _offlineManager;
  TileStore? _tileStore;

  static const String _styleUri = 'mapbox://styles/mapbox/streets-v12';
  static const double _radiusKm = 25.0; // ~50km de diámetro por zona

  Future<void> _ensureInit() async {
    _offlineManager ??= await OfflineManager.create();
    _tileStore ??= await TileStore.createDefault();
  }

  Map<String, dynamic> _bboxPolygon(double lat, double lng) {
    final deltaLat = _radiusKm / 111.0;
    final deltaLng = _radiusKm / (111.0 * math.cos(lat * math.pi / 180));
    final minLat = lat - deltaLat;
    final maxLat = lat + deltaLat;
    final minLng = lng - deltaLng;
    final maxLng = lng + deltaLng;
    return {
      'type': 'Polygon',
      'coordinates': [
        [
          [minLng, minLat],
          [maxLng, minLat],
          [maxLng, maxLat],
          [minLng, maxLat],
          [minLng, minLat],
        ]
      ],
    };
  }

  /// Descarga el estilo y los tiles de ~50km alrededor de [lat],[lng].
  /// [onProgress] recibe un valor de 0.0 a 1.0.
  Future<void> downloadRegion({
    required String regionId,
    required double lat,
    required double lng,
    required void Function(double) onProgress,
  }) async {
    await _ensureInit();

    double styleProgress = 0.0;
    double tileProgress = 0.0;
    void report() => onProgress((styleProgress + tileProgress) / 2);

    await _offlineManager!.loadStylePack(
      _styleUri,
      StylePackLoadOptions(
        glyphsRasterizationMode:
            GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
        metadata: {'tag': regionId},
        acceptExpired: false,
      ),
      (progress) {
        styleProgress = progress.requiredResourceCount == 0
            ? 1.0
            : progress.completedResourceCount /
                progress.requiredResourceCount;
        report();
      },
    );

    await _tileStore!.loadTileRegion(
      regionId,
      TileRegionLoadOptions(
        geometry: _bboxPolygon(lat, lng),
        descriptorsOptions: [
          TilesetDescriptorOptions(
            styleURI: _styleUri,
            minZoom: 0,
            maxZoom: 16,
          ),
        ],
        acceptExpired: false,
        networkRestriction: NetworkRestriction.NONE,
      ),
      (progress) {
        tileProgress = progress.requiredResourceCount == 0
            ? 1.0
            : progress.completedResourceCount /
                progress.requiredResourceCount;
        report();
      },
    );

    onProgress(1.0);
  }

  Future<void> deleteRegion(String regionId) async {
    await _ensureInit();
    try {
      await _tileStore!.removeRegion(regionId);
    } catch (_) {}
  }
}
