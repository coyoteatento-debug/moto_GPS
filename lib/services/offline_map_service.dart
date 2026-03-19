import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

enum DownloadStatus { idle, downloading, completed, failed }

class DownloadProgress {
  final int tilesCompleted;
  final int tilesTotal;
  final double percentage;
  final double estimatedMB;
  final DownloadStatus status;
  final String? error;

  const DownloadProgress({
    required this.tilesCompleted,
    required this.tilesTotal,
    required this.percentage,
    required this.estimatedMB,
    required this.status,
    this.error,
  });
}

class StoreInfo {
  final String name;
  final int tiles;
  final double sizeMB;

  const StoreInfo({
    required this.name,
    required this.tiles,
    required this.sizeMB,
  });
}

class OfflineMapService {
  static const String _defaultStore = 'moto_offline';
  static const String _osmUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static Future<void> initialize() async {
    await FMTCObjectBoxBackend().initialise();
    await FMTCStore(_defaultStore).manage.create();
  }

  static TileProvider getTileProvider({String? storeName}) {
    return FMTCStore(storeName ?? _defaultStore).getTileProvider(
      settings: FMTCTileProviderSettings(
        behavior: CacheBehavior.cacheFirst,
        cachedValidDuration: const Duration(days: 30),
      ),
    );
  }

  static Stream<DownloadProgress> downloadRegion({
    required String storeName,
    required LatLngBounds bounds,
    int minZoom = 8,
    int maxZoom = 16,
  }) async* {
    final store = FMTCStore(storeName);
    await store.manage.create();

    final region = RectangleRegion(bounds);
    final downloadable = region.toDownloadable(
      minZoom: minZoom,
      maxZoom: maxZoom,
      options: TileLayer(urlTemplate: _osmUrl),
    );

    final tileCount = downloadable.approxTiles;
    final estimatedMB = (tileCount * 25) / 1024;

    yield DownloadProgress(
      tilesCompleted: 0,
      tilesTotal: tileCount,
      percentage: 0,
      estimatedMB: estimatedMB,
      status: DownloadStatus.downloading,
    );

    int completed = 0;

    try {
      await for (final event
          in store.download.startForeground(
        region: downloadable,
        parallelThreads: 3,
        maxBufferLength: 100,
        skipExistingTiles: true,
        retryFailedRequestTiles: true,
      )) {
        if (event is TileEvent) {
          completed++;
          yield DownloadProgress(
            tilesCompleted: completed,
            tilesTotal: tileCount,
            percentage:
                tileCount > 0 ? (completed / tileCount) * 100 : 100,
            estimatedMB: estimatedMB,
            status: DownloadStatus.downloading,
          );
        }
      }

      yield DownloadProgress(
        tilesCompleted: tileCount,
        tilesTotal: tileCount,
        percentage: 100,
        estimatedMB: estimatedMB,
        status: DownloadStatus.completed,
      );
    } catch (e) {
      yield DownloadProgress(
        tilesCompleted: completed,
        tilesTotal: tileCount,
        percentage: 0,
        estimatedMB: estimatedMB,
        status: DownloadStatus.failed,
        error: e.toString(),
      );
    }
  }

  static Future<List<StoreInfo>> listStores() async {
    final storeNames = await FMTCRoot.stats.storesAvailable;
    final List<StoreInfo> result = [];
    for (final name in storeNames) {
      final store = FMTCStore(name);
      final tiles = await store.stats.length;
      final sizeKib = await store.stats.size;
      result.add(StoreInfo(
        name: name,
        tiles: tiles,
        sizeMB: sizeKib / 1024,
      ));
    }
    return result;
  }

  static Future<void> deleteStore(String name) async {
    await FMTCStore(name).manage.delete();
  }

  static Future<double> totalSizeMB() async {
    final sizeKib = await FMTCRoot.stats.size;
    return sizeKib / 1024;
  }

  static Future<void> cancelDownload(String storeName) async {
    await FMTCStore(storeName).download.cancel();
  }
}
