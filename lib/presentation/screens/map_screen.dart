import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../core/utils/geo_utils.dart';
import '../../di/providers.dart';
import '../widgets/map_tab.dart';
import '../widgets/trip_book.dart';
import '../controllers/map_controller.dart';
import 'main_menu_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  final _searchController = TextEditingController();
    Timer? _autoRecenterTimer;

  void _scheduleAutoRecenter() {
    _autoRecenterTimer?.cancel();
    _autoRecenterTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      final current = ref.read(mapControllerProvider);
      if (current.navigating && current.userIsExploring) {
        ref.read(mapControllerProvider.notifier).recenter();
      }
    });
  }

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
    _autoRecenterTimer?.cancel();
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
    final state = ref.watch(mapControllerProvider.select((s) => (
      navigating: s.navigating,
      showSearch: s.showSearch,
      userIsExploring: s.userIsExploring,
      isSatellite: s.isSatellite,
      isNightMode: s.isNightMode,
      waypoints: s.waypoints,
      isSelectingWaypoints: s.isSelectingWaypoints,
      showWaypointArrival: s.showWaypointArrival,
      waypointArrivalMessage: s.waypointArrivalMessage,
      routeDrawn: s.routeDrawn,
      showTapConfirm: s.showTapConfirm,
      isRecalculating: s.isRecalculating,
      showLowFuelWarning: s.showLowFuelWarning,
      routeDistance: s.routeDistance,
      routeDuration: s.routeDuration,
      tappedLat: s.tappedLat,
      tappedLng: s.tappedLng,
      selectedPlace: s.selectedPlace,
      alternateRoutes: s.alternateRoutes,
      selectedRouteIndex: s.selectedRouteIndex,
      userAvatarImage: s.userAvatarImage,
      handsFreeActive: s.handsFreeActive,
      savedPois: s.savedPois,
      searchLoading: s.searchLoading,
      searchResults: s.searchResults,
      currentTabIndex: s.currentTabIndex,
      trips: s.trips,
    )));
    final controller = ref.read(mapControllerProvider.notifier);

    return Scaffold(
      bottomNavigationBar: state.navigating
          ? null
          : BottomNavigationBar(
              currentIndex: state.currentTabIndex,
              onTap: (i) {
                controller.setTabIndex(i);
                final hasPosition =
                    ref.read(mapControllerProvider).currentPosition != null;
                if (i == 0 && hasPosition) {
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
          MapTab(
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
            routeDrawn: state.routeDrawn,
            showTapConfirm: state.showTapConfirm,
            isRecalculating: state.isRecalculating,
            showLowFuelWarning: state.showLowFuelWarning,
            routeDistance: state.routeDistance,
            routeDuration: state.routeDuration,
            tappedLat: state.tappedLat,
            tappedLng: state.tappedLng,
            selectedPlace: state.selectedPlace,
            alternateRoutes: state.alternateRoutes,
            selectedRouteIndex: state.selectedRouteIndex,
            userAvatarImage: state.userAvatarImage,
            searchController: _searchController,
            handsFreeActive: state.handsFreeActive,
            onToggleHandsFree: controller.toggleHandsFree,
            savedPois: state.savedPois,
            searchLoading: state.searchLoading,
            searchResults: state.searchResults,
            onMapCreated: controller.onMapCreated,
            onMapTap: (ctx) => controller.onMapTap(
              ctx.point.coordinates.lat.toDouble(),
              ctx.point.coordinates.lng.toDouble(),
            ),
            onCameraChange: (_) {
              final isProgrammatic =
                  ref.read(mapControllerProvider).isProgrammaticMove;
              if (!isProgrammatic) {
                _scheduleAutoRecenter();
              }
              if (isProgrammatic) {
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
              if (bytes == null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No se pudo guardar la foto. Intenta con una imagen más pequeña.'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            onVoiceSearch: _startVoiceSearch,
            isListening: controller.isListening,
            onSatelliteToggle: controller.toggleSatellite,
            onNightModeToggle: controller.toggleNightMode,
            onTapConfirm: controller.confirmTappedDestination,
            onTapCancel: controller.cancelTap,
            onCancelRoute: controller.cancelRoute,
            onStartNavigation: controller.startNavigation,
            onRouteSelect: controller.selectRoute,
            onOpenMenu: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MainMenuScreen()),
            ),
          ),
          TripBook(trips: state.trips),
        ],
      ),
    );
  }
}
