import 'package:flutter_map/flutter_map.dart';
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
  static Future<void> initialize() async {}

  static TileProvider getTileProvider({String? storeName}) {
    return NetworkTileProvider();
  }

  static Stream<DownloadProgress> downloadRegion({
    required String storeName,
    required LatLngBounds bounds,
    int minZoom = 8,
    int maxZoom = 16,
  }) async* {
    yield const DownloadProgress(
      tilesCompleted: 0,
      tilesTotal: 0,
      percentage: 100,
      estimatedMB: 0,
      status: DownloadStatus.completed,
    );
  }

  static Future<List<StoreInfo>> listStores() async => [];

  static Future<void> deleteStore(String name) async {}

  static Future<double> totalSizeMB() async => 0.0;

  static Future<void> cancelDownload(String storeName) async {}
}
