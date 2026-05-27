import 'dart:convert';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'dart:typed_data';

class MapService {
  MapService();

  // ── Estilo de carreteras tipo Riser ───────────────────
  Future<void> applyCustomRoadStyle(mapbox.MapboxMap map) async {
    final style = await map.style;

    final Map<String, String> lineColors = {
      'road-motorway': '#FF6500',
      'road-motorway-case': '#CC4E00',
      'road-motorway-link': '#FF6500',
      'road-motorway-link-case': '#CC4E00',
      'road-motorway-trunk': '#FF6500',
      'road-motorway-trunk-case': '#CC4E00',
      'road-trunk': '#FF6500',
      'road-trunk-case': '#CC4E00',
      'road-trunk-link': '#FF6500',
      'road-trunk-link-case': '#CC4E00',
      'road-primary': '#FFD600',
      'road-primary-case': '#C9A800',
      'road-primary-link': '#FFD600',
      'road-secondary': '#FFE566',
      'road-secondary-case': '#C9B400',
      'road-secondary-link': '#FFE566',
      'road-secondary-tertiary': '#FFE566',
      'road-secondary-tertiary-case': '#C9B400',
      'road-tertiary': '#FFF0A0',
      'road-tertiary-case': '#D4C87A',
      'road-street': '#D6D6D6',
      'road-street-case': '#B0B0B0',
      'road-street-low': '#D6D6D6',
      'road-service': '#C4C4C4',
      'road-service-case': '#A0A0A0',
      'road-pedestrian': '#E0E0E0',
      'road-pedestrian-case': '#C8C8C8',
      'road-path': '#DADADA',
      'road-path-bg': '#C8C8C8',
    };

    for (final entry in lineColors.entries) {
      try {
        await style.setStyleLayerProperty(
          entry.key, 'line-color', json.encode(entry.value),
        );
      } catch (_) {}
    }

    for (final bg in ['land', 'background', 'landcover']) {
      try {
        await style.setStyleLayerProperty(
          bg, 'background-color', json.encode('#EFEFEF'),
        );
      } catch (_) {}
    }
  }

  // ── Dibujar rutas en el mapa ──────────────────────────
  Future<void> drawRouteOnMap(
    mapbox.MapboxMap map,
    Map<String, dynamic> geometry,
    List<Map<String, dynamic>> alternateRoutes,
  ) async {
    final style = await map.style;

    // Limpiar rutas anteriores
    for (int i = 0; i < 5; i++) {
      try { await style.removeStyleLayer('route-layer-\$i'); } catch (_) {}
      try { await style.removeStyleSource('route-source-\$i'); } catch (_) {}
    }
    try { await style.removeStyleLayer('route-layer'); } catch (_) {}
    try { await style.removeStyleSource('route-source'); } catch (_) {}

    // Rutas alternas (gris)
    for (int i = 1; i < alternateRoutes.length; i++) {
      final altGeom = alternateRoutes[i]['geometry'];
      if (altGeom == null) continue;

      await style.addSource(mapbox.GeoJsonSource(
        id: 'route-source-\$i',
        data: json.encode({
          'type': 'Feature',
          'geometry': altGeom,
        }),
      ));
      await style.addLayer(mapbox.LineLayer(
        id: 'route-layer-\$i', 
        sourceId: 'route-source-\$i',
        lineColor: const Color(0xFF90A4AE).value, 
        lineWidth: 5.0,
        lineCap: mapbox.LineCap.ROUND, 
        lineJoin: mapbox.LineJoin.ROUND,
      ));
    }

    // Ruta principal (azul)
    await style.addSource(mapbox.GeoJsonSource(
      id: 'route-source-0',
      data: json.encode({'type': 'Feature', 'geometry': geometry}),
    ));
    await style.addLayer(mapbox.LineLayer(
      id: 'route-layer-0', 
      sourceId: 'route-source-0',
      lineColor: const Color(0xFF1976D2).value, 
      lineWidth: 6.0,
      lineCap: mapbox.LineCap.ROUND, 
      lineJoin: mapbox.LineJoin.ROUND,
    ));
  }

  // ── Actualizar ruta restante ──────────────────────────
  Future<void> updateRemainingRoute(
    mapbox.MapboxMap map,
    List<List<double>> remaining,
  ) async {
    if (remaining.length < 2) return;
    try {
      final style = await map.style;
      await style.setStyleSourceProperty(
        'route-source-0',
        'data',
        json.encode({
          'type': 'Feature',
          'geometry': {'type': 'LineString', 'coordinates': remaining},
        }),
      );
    } catch (e) {
      print('[MapService] updateRemainingRoute error: \$e');
    }
  }

  // ── Capa de gasolineras ───────────────────────────────
  Future<void> updateGasolineraLayer(
    mapbox.MapboxMap map,
    String geoJson,
  ) async {
    try {
      final style = await map.style;
      try { await style.removeStyleLayer('gasolineras-layer'); } catch (_) {}
      try { await style.removeStyleLayer('gasolineras-label'); } catch (_) {}
      try { await style.removeStyleSource('gasolineras-source'); } catch (_) {}

      await style.addSource(mapbox.GeoJsonSource(
        id: 'gasolineras-source', 
        data: geoJson,
      ));

      // Círculo naranja
      await style.addLayer(mapbox.CircleLayer(
        id: 'gasolineras-layer',
        sourceId: 'gasolineras-source',
        circleRadius: 8.0,
        circleColor: const Color(0xFFFF6D00).value,
        circleStrokeWidth: 2.0,
        circleStrokeColor: const Color(0xFFFFFFFF).value,
      ));

      // Etiqueta de nombre
      await style.addLayer(mapbox.SymbolLayer(
        id: 'gasolineras-label',
        sourceId: 'gasolineras-source',
        textField: '{name}',
        textSize: 10.0,
        textOffset: const [0.0, 1.8],
        textAllowOverlap: false,
        textOptional: true,
        textColor: const Color(0xFFFF6D00).value,
      ));
    } catch (e) {
      print('[MapService] updateGasolineraLayer error: \$e');
    }
  }

  // ── Limpiar todas las capas de ruta ──────────────────
  Future<void> clearRouteLayers(mapbox.MapboxMap map) async {
    try {
      final style = await map.style;
      for (int i = 0; i < 5; i++) {
        try { await style.removeStyleLayer('route-layer-\$i'); } catch (_) {}
        try { await style.removeStyleSource('route-source-\$i'); } catch (_) {}
      }
      try { await style.removeStyleLayer('route-layer'); } catch (_) {}
      try { await style.removeStyleSource('route-source'); } catch (_) {}
    } catch (e) {
      print('[MapService] clearRouteLayers error: \$e');
    }
  }

  // ── Resaltar ruta seleccionada ────────────────────────
  Future<void> highlightRoute(
    mapbox.MapboxMap map,
    int selectedIndex,
    int totalRoutes,
  ) async {
    try {
      final style = await map.style;
      for (int j = 0; j < totalRoutes; j++) {
        await style.setStyleLayerProperty(
          'route-layer-\$j', 
          'line-color',
          json.encode(j == selectedIndex ? '#1976D2' : '#90A4AE'),
        );
        await style.setStyleLayerProperty(
          'route-layer-\$j', 
          'line-width',
          json.encode(j == selectedIndex ? 6.0 : 4.0),
        );
      }
    } catch (e) {
      print('[MapService] highlightRoute error: \$e');
    }
  }

  // ── Crear o actualizar marcador de moto ───────────────
  // FIX: Usar un lock real en lugar de bool para evitar race conditions
  final Map<String, bool> _markerLocks = {};

  Future<mapbox.PointAnnotation?> updateMotoMarker({
    required mapbox.PointAnnotationManager manager,
    required mapbox.PointAnnotation? current,
    required double lat,
    required double lng,
    required double bearing,
    required Uint8List markerImage,
    required bool isAvatar,
  }) async {
    final lockKey = 'moto_marker';

    // Si ya estamos creando, esperar un poco y reintentar
    if (_markerLocks[lockKey] == true) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_markerLocks[lockKey] == true) return current;
    }

    _markerLocks[lockKey] = true;

    try {
      if (current != null) {
        // Actualizar posición del marcador existente
        current.geometry = mapbox.Point(
          coordinates: mapbox.Position(lng, lat));
        current.iconRotate = isAvatar ? 0.0 : bearing;
        await manager.update(current);
        return current;
      } else {
        final annotation = await manager.create(
          mapbox.PointAnnotationOptions(
            geometry: mapbox.Point(
              coordinates: mapbox.Position(lng, lat)),
            image: markerImage,
            iconSize: 1.2,
            iconAnchor: mapbox.IconAnchor.CENTER,
            iconRotate: isAvatar ? 0.0 : bearing,
          ),
        );
        return annotation;
      }
    } catch (e) {
      print('[MapService] updateMotoMarker error: \$e');
      return current;
    } finally {
      _markerLocks[lockKey] = false;
    }
  }

  // ── Crear o reemplazar marcador de destino ────────────
  Future<mapbox.PointAnnotation?> updateDestinationMarker({
    required mapbox.PointAnnotationManager manager,
    required mapbox.PointAnnotation? current,
    required double lat,
    required double lng,
    required Uint8List pinImage,
  }) async {
    if (current != null) {
      try { await manager.delete(current); } catch (_) {}
    }
    try {
      return await manager.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(lng, lat)),
          image: pinImage,
          iconSize: 1.2,
          iconAnchor: mapbox.IconAnchor.BOTTOM,
        ),
      );
    } catch (e) {
      print('[MapService] updateDestinationMarker error: \$e');
      return null;
    }
  }

  // ── Eliminar marcador ─────────────────────────────────
  Future<void> deleteAnnotation(
    mapbox.PointAnnotationManager manager,
    mapbox.PointAnnotation annotation,
  ) async {
    try { await manager.delete(annotation); } catch (e) {
      print('[MapService] deleteAnnotation error: \$e');
    }
  }
}
