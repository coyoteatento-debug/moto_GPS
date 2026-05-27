import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../core/utils/geo_utils.dart';
import '../../di/providers.dart';
import '../widgets/map_tab.dart';
import '../widgets/trip_book.dart';
import '../controllers/map_controller.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  final _searchController = TextEditingController();
  DateTime _lastUserInteraction = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final controller = ref.read(mapControllerProvider.notifier);
    controller.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.requestPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final controller = ref.read(mapControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
        controller.onAppBackground();
        break;
      case AppLifecycleState.resumed:
        controller.onAppForeground();
        break;
      default:
        break;
    }
  }

  Future<void> _startVoiceSearch() async {
    final controller = ref.read(mapControllerProvider.notifier);
    final available = await controller.ensureSpeechAvailable();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reconocimiento de voz no disponible'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (controller.isListening) {
      await controller.stopVoiceSearch();
      setState(() {});
      return;
    }

    if (!ref.read(mapControllerProvider).showSearch) {
      controller.state = controller.state.copyWith(showSearch: true);
    }

    setState(() {});
    await controller.startVoiceSearch(
      onResult: (text) {
        _searchController.text = text;
        controller.searchPlaces(text);
      },
      onListeningStarted: () => setState(() {}),
      onListeningStopped: () => setState(() {}),
    );
  }

  void _showSnack(String msg, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapControllerProvider);
    final controller = ref.read(mapControllerProvider.notifier);

    return Scaffold(
      bottomNavigationBar: state.navigating
          ? null
          : BottomNavigationBar(
              currentIndex: state.currentTabIndex,
              onTap: (i) {
                controller.setTabIndex(i);
                if (i == 0 && state.currentPosition != null) {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    controller.recenter();
                  });
                }
              },
              backgroundColor: Colors.black87,
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.grey,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.map_outlined),
                  activeIcon: Icon(Icons.map),
                  label: 'Mapa',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.menu_book_outlined),
                  activeIcon: Icon(Icons.menu_book),
                  label: 'Libro de viaje',
                ),
              ],
            ),
      body: IndexedStack(
        index: state.currentTabIndex,
        children: [
          _buildMapTab(state, controller),
          TripBook(trips: state.trips),
        ],
      ),
    );
  }

  Widget _buildMapTab(MapState state, MapController controller) {
    final geo = ref.read(geoUtilsProvider);

    return MapTab(
      navigating: state.navigating,
      showSearch: state.showSearch,
      userIsExploring: state.userIsExploring,
      isSatellite: state.isSatellite,
      isNightMode: state.isNightMode,
      waypoints: state.waypoints,
      isSelectingWaypoints: state.isSelectingWaypoints,
      showWaypointArrival: state.showWaypointArrival,
      waypointArrivalMessage: state.waypointArrivalMessage,
      onWaypointModeToggle: controller.toggleWaypointMode,
      onWaypointDone: controller.finishWaypointSelection,
      onWaypointClear: controller.clearWaypointsAndReRoute,
      gasolinerasVisible: state.gasolinerasVisible,
      gasolinerasLoading: state.gasolinerasLoading,
      routeDrawn: state.routeDrawn,
      showTapConfirm: state.showTapConfirm,
      isRecalculating: state.isRecalculating,
      routeDistance: state.routeDistance,
      routeDuration: state.routeDuration,
      currentInstruction: state.currentInstruction,
      distanceToNextManeuver: state.distanceToNextManeuver,
      currentSpeed: state.currentSpeed,
      speedLimit: state.speedLimit,
      tappedLat: state.tappedLat,
      tappedLng: state.tappedLng,
      selectedPlace: state.selectedPlace,
      alternateRoutes: state.alternateRoutes,
      selectedRouteIndex: state.selectedRouteIndex,
      userAvatarImage: state.userAvatarImage,
      searchController: _searchController,
      searchLoading: state.searchLoading,
      searchResults: state.searchResults,
      onMapCreated: controller.onMapCreated,
      onMapTap: (ctx) => controller.onMapTap(
        ctx.point.coordinates.lat.toDouble(),
        ctx.point.coordinates.lng.toDouble(),
      ),
      onCameraChange: (_) {
        if (!state.isProgrammaticMove) {
          _lastUserInteraction = DateTime.now();
        }
        if (state.isProgrammaticMove) {
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted) controller.setIsProgrammaticMove(false);
          });
        } else {
          controller.onCameraChanged();
        }
      },
      onSearchToggle: () {
        controller.state = controller.state.copyWith(
          showSearch: !state.showSearch,
          searchResults: !state.showSearch ? const [] : state.searchResults,
        );
        if (state.showSearch) _searchController.clear();
      },
      onSearchClose: () {
        controller.state = controller.state.copyWith(
          showSearch: false,
          searchResults: const [],
        );
        _searchController.clear();
      },
      onSearchChanged: controller.searchPlaces,
      onSearchSelect: controller.selectSearchResult,
      onRecenter: controller.recenter,
      onAvatarPick: () async {
        final bytes = await controller.pickUserAvatar();
        if (bytes == null && mounted) {
          _showSnack('Imagen muy grande, intenta con una más pequeña');
        }
      },
      onVoiceSearch: _startVoiceSearch,
      isListening: controller.isListening,
      onGasolinerasToggle: controller.toggleGasolineras,
      onSatelliteToggle: controller.toggleSatellite,
      onNightModeToggle: controller.toggleNightMode,
      onTapConfirm: controller.confirmTappedDestination,
      onTapCancel: controller.cancelTap,
      onCancelRoute: controller.cancelRoute,
      onStartNavigation: controller.startNavigation,
      onRouteSelect: controller.selectRoute,
    );
  }
}
