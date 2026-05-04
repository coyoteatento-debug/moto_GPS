import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'search_modal.dart';
import '../../core/services/speed_limit_service.dart';

// ── Botón de capas expandible ─────────────────────────
class _LayersButton extends StatefulWidget {
  final bool isSatellite;
  final bool isNightMode;
  final VoidCallback onSatelliteToggle;
  final VoidCallback onNightModeToggle;

  const _LayersButton({
    required this.isSatellite,
    required this.isNightMode,
    required this.onSatelliteToggle,
    required this.onNightModeToggle,
  });

  @override
  State<_LayersButton> createState() => _LayersButtonState();
}

class _LayersButtonState extends State<_LayersButton>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  Widget _subBtn({
    required IconData icon,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          onTap();
          _toggle();
        },
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))
            ],
          ),
          child: Icon(icon,
              color: active ? Colors.white : activeColor, size: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sub-botón modo nocturno
        FadeTransition(
          opacity: _fadeAnim,
          child: SizeTransition(
            sizeFactor: _fadeAnim,
            axis: Axis.vertical,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _subBtn(
                icon: Icons.nightlight_round,
                active: widget.isNightMode,
                activeColor: Colors.indigo,
                onTap: widget.onNightModeToggle,
                tooltip: widget.isNightMode ? 'Modo día' : 'Modo nocturno',
              ),
            ),
          ),
        ),
        // Sub-botón satélite
        FadeTransition(
          opacity: _fadeAnim,
          child: SizeTransition(
            sizeFactor: _fadeAnim,
            axis: Axis.vertical,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _subBtn(
                icon: Icons.satellite_alt,
                active: widget.isSatellite,
                activeColor: Colors.blue.shade700,
                onTap: widget.onSatelliteToggle,
                tooltip: widget.isSatellite ? 'Mapa normal' : 'Vista satélite',
              ),
            ),
          ),
        ),
        // Botón principal de capas
        GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: (_expanded || widget.isSatellite || widget.isNightMode)
                  ? Colors.blueGrey.shade700
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))
              ],
            ),
            child: Icon(
              _expanded ? Icons.close : Icons.layers,
              color: (_expanded || widget.isSatellite || widget.isNightMode)
                  ? Colors.white
                  : Colors.blueGrey.shade700,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}

class MapTab extends StatelessWidget {
  // ── Estado del mapa ───────────────────────────────────
  final bool navigating;
  final bool showSearch;
  final bool userIsExploring;
  final bool isSatellite;
  final bool isNightMode;
  final bool gasolinerasVisible;
  final bool gasolinerasLoading;
  final bool routeDrawn;
  final bool showTapConfirm;
  final bool isRecalculating;

  // ── Datos de ruta ─────────────────────────────────────
  final String routeDistance;
  final String routeDuration;
  final String currentInstruction;
  final double distanceToNextManeuver;
  final double currentSpeed;
  final int? speedLimit;
  final double? tappedLat;
  final double? tappedLng;
  final Map<String, dynamic>? selectedPlace;
  final List<Map<String, dynamic>> alternateRoutes;
  final int selectedRouteIndex;

  // ── Avatar ─────────────────────────────────────────────
  final Uint8List? userAvatarImage;

  // ── Búsqueda ──────────────────────────────────────────
  final TextEditingController searchController;
  final bool searchLoading;
  final List<Map<String, dynamic>> searchResults;

  // ── Callbacks mapa ─────────────────────────────────────
  final void Function(mapbox.MapboxMap) onMapCreated;
  final void Function(mapbox.MapContentGestureContext) onMapTap;
  final void Function(mapbox.CameraChangedEventData) onCameraChange;

  // ── Callbacks UI ───────────────────────────────────────
  final VoidCallback onSearchToggle;
  final VoidCallback onSearchClose;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Map<String, dynamic>> onSearchSelect;
  final VoidCallback onRecenter;
  final VoidCallback onAvatarPick;
  final VoidCallback onVoiceSearch;
  final bool isListening;
  final VoidCallback onGasolinerasToggle;
  final VoidCallback onSatelliteToggle;
  final VoidCallback onNightModeToggle;
  final VoidCallback onTapConfirm;
  final VoidCallback onTapCancel;
  final VoidCallback onCancelRoute;
  final VoidCallback onStartNavigation;
  final ValueChanged<int> onRouteSelect;

  MapTab({
    super.key,
    required this.navigating,
    required this.showSearch,
    required this.userIsExploring,
    required this.isSatellite,
    required this.isNightMode,
    required this.gasolinerasVisible,
    required this.gasolinerasLoading,
    required this.routeDrawn,
    required this.showTapConfirm,
    required this.isRecalculating,
    required this.routeDistance,
    required this.routeDuration,
    required this.currentInstruction,
    required this.distanceToNextManeuver,
    required this.currentSpeed,
    required this.speedLimit,
    required this.tappedLat,
    required this.tappedLng,
    required this.selectedPlace,
    required this.alternateRoutes,
    required this.selectedRouteIndex,
    required this.userAvatarImage,
    required this.searchController,
    required this.searchLoading,
    required this.searchResults,
    required this.onMapCreated,
    required this.onMapTap,
    required this.onCameraChange,
    required this.onSearchToggle,
    required this.onSearchClose,
    required this.onSearchChanged,
    required this.onSearchSelect,
    required this.onRecenter,
    required this.onAvatarPick,
    required this.onVoiceSearch,
    required this.isListening,
    required this.onGasolinerasToggle,
    required this.onSatelliteToggle,
    required this.onNightModeToggle,
    required this.onTapConfirm,
    required this.onTapCancel,
    required this.onCancelRoute,
    required this.onStartNavigation,
    required this.onRouteSelect,
  });

  IconData _maneuverIcon(String instruction) {
    final i = instruction.toLowerCase();
    if (i.contains('izquierda'))                         return Icons.turn_left;
    if (i.contains('derecha'))                           return Icons.turn_right;
    if (i.contains('gira'))                              return Icons.turn_slight_right;
    if (i.contains('rotonda') || i.contains('redondel')) return Icons.roundabout_left;
    if (i.contains('destino') || i.contains('llegada'))  return Icons.flag;
    if (i.contains('continúa') || i.contains('sigue'))   return Icons.straight;
    return Icons.navigation;
  }

  Widget _tripStat(IconData icon, String label, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(
          color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    ]);
  }

  Widget _buildSpeedometer() {
    final status = SpeedStatus.evaluate(currentSpeed, speedLimit);

    final bgColor = switch (status.level) {
      SpeedAlertLevel.danger  => Colors.red[700]!,
      SpeedAlertLevel.warning => Colors.orange[700]!,
      SpeedAlertLevel.normal  => Colors.black87,
    };

    final textColor = switch (status.level) {
      SpeedAlertLevel.danger  => Colors.white,
      SpeedAlertLevel.warning => Colors.white,
      SpeedAlertLevel.normal  => Colors.white,
    };

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: status.level != SpeedAlertLevel.normal
            ? [BoxShadow(
                color: bgColor.withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
              )]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${currentSpeed.toStringAsFixed(0)}',
            style: TextStyle(
              color:      textColor,
              fontSize:   40,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'km/h',
            style: TextStyle(color: textColor.withOpacity(0.8)),
          ),
          if (status.speedLimit != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Límite: ${status.speedLimit} km/h',
                style: TextStyle(
                  color:    textColor.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [

      // ── Mapa ───────────────────────────────────────────
      SizedBox.expand(
        child: mapbox.MapWidget(
          key: const ValueKey('mapWidget'),
          onMapCreated: onMapCreated,
          styleUri: 'mapbox://styles/mapbox/streets-v12',
          onTapListener: onMapTap,
          cameraOptions: mapbox.CameraOptions(zoom: 15.0, pitch: 0.0),
          onCameraChangeListener: onCameraChange,
        ),
      ),

      // ── Botón búsqueda ─────────────────────────────────
      if (!navigating)
        Positioned(
          top: 50, right: 16,
          child: GestureDetector(
            onTap: onSearchToggle,
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(
                    color: Colors.black38, blurRadius: 8,
                    offset: Offset(0, 2))],
              ),
              child: const Icon(Icons.search, color: Colors.blue, size: 24),
            ),
          ),
        ),

      // ── Botón micrófono flotante ───────────────────────
      if (!navigating)
        Positioned(
          top: 50, right: 70,
          child: GestureDetector(
            onTap: onVoiceSearch,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: isListening ? Colors.red : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                  color: isListening
                      ? Colors.red.withOpacity(0.5)
                      : Colors.black38,
                  blurRadius: isListening ? 12 : 8,
                  offset: const Offset(0, 2),
                )],
              ),
              child: Icon(
                isListening ? Icons.mic : Icons.mic_none,
                color: isListening ? Colors.white : Colors.red,
                size: 24,
              ),
            ),
          ),
        ),

      // ── Modal búsqueda ─────────────────────────────────
      if (showSearch && !navigating)
        Positioned(
          top: 0, left: 0, right: 0,
          child: SearchModal(
            controller:  searchController,
            isLoading:   searchLoading,
            results:     searchResults,
            onChanged:   onSearchChanged,
            onClose:     onSearchClose,
            onSelect:    onSearchSelect,
            onVoiceSearch: onVoiceSearch,
            isListening:   isListening,
          ),
        ),

      // ── Botón recentrar ────────────────────────────────
      if (userIsExploring && !navigating)
        Positioned(
          bottom: (routeDrawn && alternateRoutes.length > 1) ? 310 : 110,
          right: 16,
          child: GestureDetector(
            onTap: onRecenter,
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: Colors.blue[700],
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(
                    color: Colors.black38, blurRadius: 8,
                    offset: Offset(0, 2))],
              ),
              child: const Icon(
                  Icons.my_location, color: Colors.white, size: 22),
            ),
          ),
        ),

      // ── Botón avatar ───────────────────────────────────
      if (!navigating && !showSearch)
        Positioned(
          top: 106, right: 16,
          child: GestureDetector(
            onTap: onAvatarPick,
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blue, width: 2),
                boxShadow: const [BoxShadow(
                    color: Colors.black38, blurRadius: 8,
                    offset: Offset(0, 2))],
                image: userAvatarImage != null
                    ? DecorationImage(
                        image: MemoryImage(userAvatarImage!),
                        fit: BoxFit.cover)
                    : null,
                color: Colors.white,
              ),
              child: userAvatarImage == null
                  ? const Icon(Icons.person_add,
                      color: Colors.blue, size: 22)
                  : null,
            ),
          ),
        ),

      // ── Botón gasolineras ──────────────────────────────
      if (!navigating)
        Positioned(
          bottom: 230, right: 16,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onGasolinerasToggle,
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: gasolinerasVisible
                    ? Colors.orange[700] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(
                    color: Colors.black38, blurRadius: 8,
                    offset: Offset(0, 2))],
              ),
              child: gasolinerasLoading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.orange[700]),
                    )
                  : Icon(Icons.local_gas_station,
                      color: gasolinerasVisible
                          ? Colors.white : Colors.orange[700],
                      size: 24),
            ),
          ),
        ),

      // ── Botón capas (satélite + modo nocturno) ─────────
      if (!navigating)
        Positioned(
          bottom: 170, right: 16,
          child: _LayersButton(
            isSatellite:       isSatellite,
            isNightMode:       isNightMode,
            onSatelliteToggle: onSatelliteToggle,
            onNightModeToggle: onNightModeToggle,
          ),
        ),

      // ── Confirmar tap ──────────────────────────────────
      if (showTapConfirm && !navigating)
        Positioned(
          bottom: 30, left: 16, right: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(
                  color: Colors.black26, blurRadius: 10,
                  offset: Offset(0, 4))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.location_on, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              const Text('¿Ir a este lugar?',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                'Lat: ${tappedLat?.toStringAsFixed(5)}  '
                'Lng: ${tappedLng?.toStringAsFixed(5)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: onTapCancel,
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: const Text('Cancelar',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  onPressed: onTapConfirm,
                  icon: const Icon(Icons.directions, color: Colors.white),
                  label: const Text('Trazar ruta',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
              ]),
            ]),
          ),
        ),

      // ── Selector rutas alternas ────────────────────────
      if (routeDrawn && !navigating && alternateRoutes.length > 1)
        Positioned(
          bottom: 185, left: 16, right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(
                  color: Colors.black26, blurRadius: 8,
                  offset: Offset(0, 2))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(alternateRoutes.length, (i) {
                final r        = alternateRoutes[i];
                final selected = i == selectedRouteIndex;
                return GestureDetector(
                  onTap: () => onRouteSelect(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.blue[700] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Ruta ${i + 1}', style: TextStyle(
                            fontSize: 11,
                            color: selected
                                ? Colors.white : Colors.grey,
                            fontWeight: FontWeight.w600)),
                        Text(r['distance'], style: TextStyle(
                            fontSize: 13,
                            color: selected
                                ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold)),
                        Text(r['duration'], style: TextStyle(
                            fontSize: 11,
                            color: selected
                                ? Colors.white70 : Colors.grey)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),

      // ── Panel ruta ─────────────────────────────────────
      if (routeDrawn && !navigating && !showTapConfirm)
        Positioned(
          bottom: (alternateRoutes.length > 1) ? 185 + 70 : 30,
          left: 16, right: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(
                  color: Colors.black26, blurRadius: 10,
                  offset: Offset(0, 4))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(selectedPlace?['name'] ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.directions_bike,
                      color: Colors.blue, size: 18),
                  const SizedBox(width: 6),
                  Text('$routeDistance  •  $routeDuration',
                      style: TextStyle(
                          color: Colors.grey[700], fontSize: 14)),
                ],
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: onCancelRoute,
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: const Text('Cancelar',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  onPressed: onStartNavigation,
                  icon: const Icon(Icons.navigation, color: Colors.white),
                  label: const Text('¡Ir!', style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
              ]),
            ]),
          ),
        ),

      // ── Panel navegando ────────────────────────────────
      if (navigating)
        Positioned(
          bottom: 30, left: 20, right: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildSpeedometer(),
              ElevatedButton.icon(
                onPressed: onCancelRoute,
                icon: const Icon(Icons.close, color: Colors.white),
                label: const Text('Salir',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),

      // ── Banner recalculando ────────────────────────────
      if (navigating && isRecalculating)
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            color: Colors.orange[700],
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Recalculando ruta...',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ],
            ),
          ),
        ),

      // ── Banner turn-by-turn ────────────────────────────
      if (navigating && currentInstruction.isNotEmpty && !isRecalculating)
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1565C0),
              borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20)),
              boxShadow: [BoxShadow(
                  color: Colors.black38, blurRadius: 10,
                  offset: Offset(0, 3))],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(_maneuverIcon(currentInstruction),
                    color: Colors.white, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(currentInstruction,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      distanceToNextManeuver >= 1000
                          ? '${(distanceToNextManeuver / 1000).toStringAsFixed(1)} km'
                          : '${distanceToNextManeuver.toStringAsFixed(0)} m',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ],
                )),
              ],
            ),
          ),
        ),

      // ── Velocímetro modo libre ─────────────────────────
      if (!navigating && !routeDrawn && !showTapConfirm)
        Positioned(
          bottom: 30, left: 20,
          child: _buildSpeedometer(),
        ),
    ]);
  }
}
