import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/models/trip_record.dart';

// ── Estado inmutable ──────────────────────────────────────
class MapState {
  final double currentSpeed;
  final Position? currentPosition;
  final bool navigating;
  final bool routeDrawn;
  final bool showSearch;
  final bool showTapConfirm;
  final bool userIsExploring;
  final bool isSatellite;
  final bool gasolinerasVisible;
  final bool gasolinerasLoading;
  final bool isRecalculating;
  final bool searchLoading;
  final bool isProgrammaticMove;
  final bool initialLocationSet;
  final String routeDistance;
  final String routeDuration;
  final String currentInstruction;
  final double distanceToNextManeuver;
  final double? tappedLat;
  final double? tappedLng;
  final int currentStepIndex;
  final int selectedRouteIndex;
  final int currentTabIndex;
  final List<Map<String, dynamic>> searchResults;
  final List<Map<String, dynamic>> alternateRoutes;
  final List<Map<String, dynamic>> routeSteps;
  final List<List<double>> routeCoordinates;
  final List<TripRecord> trips;
  final Map<String, dynamic>? selectedPlace;
  final Uint8List? userAvatarImage;
  final Uint8List? pinImage;

  const MapState({
    this.currentSpeed           = 0.0,
    this.currentPosition,
    this.navigating             = false,
    this.routeDrawn             = false,
    this.showSearch             = false,
    this.showTapConfirm         = false,
    this.userIsExploring        = false,
    this.isSatellite            = false,
    this.gasolinerasVisible     = false,
    this.gasolinerasLoading     = false,
    this.isRecalculating        = false,
    this.searchLoading          = false,
    this.isProgrammaticMove     = false,
    this.initialLocationSet     = false,
    this.routeDistance          = '',
    this.routeDuration          = '',
    this.currentInstruction     = '',
    this.distanceToNextManeuver = 0.0,
    this.tappedLat,
    this.tappedLng,
    this.currentStepIndex       = 0,
    this.selectedRouteIndex     = 0,
    this.currentTabIndex        = 0,
    this.searchResults          = const [],
    this.alternateRoutes        = const [],
    this.routeSteps             = const [],
    this.routeCoordinates       = const [],
    this.trips                  = const [],
    this.selectedPlace,
    this.userAvatarImage,
    this.pinImage,
  });

  MapState copyWith({
    double?                    currentSpeed,
    Position?                  currentPosition,
    bool?                      navigating,
    bool?                      routeDrawn,
    bool?                      showSearch,
    bool?                      showTapConfirm,
    bool?                      userIsExploring,
    bool?                      isSatellite,
    bool?                      gasolinerasVisible,
    bool?                      gasolinerasLoading,
    bool?                      isRecalculating,
    bool?                      searchLoading,
    bool?                      isProgrammaticMove,
    bool?                      initialLocationSet,
    String?                    routeDistance,
    String?                    routeDuration,
    String?                    currentInstruction,
    double?                    distanceToNextManeuver,
    double?                    tappedLat,
    double?                    tappedLng,
    int?                       currentStepIndex,
    int?                       selectedRouteIndex,
    int?                       currentTabIndex,
    List<Map<String, dynamic>>? searchResults,
    List<Map<String, dynamic>>? alternateRoutes,
    List<Map<String, dynamic>>? routeSteps,
    List<List<double>>?        routeCoordinates,
    List<TripRecord>?          trips,
    Map<String, dynamic>?      selectedPlace,
    Uint8List?                 userAvatarImage,
    Uint8List?                 pinImage,
    // flags para limpiar nullables
    bool clearCurrentPosition  = false,
    bool clearSelectedPlace    = false,
    bool clearTappedLat        = false,
    bool clearTappedLng        = false,
  }) {
    return MapState(
      currentSpeed:           currentSpeed           ?? this.currentSpeed,
      currentPosition:        clearCurrentPosition   ? null : currentPosition  ?? this.currentPosition,
      navigating:             navigating             ?? this.navigating,
      routeDrawn:             routeDrawn             ?? this.routeDrawn,
      showSearch:             showSearch             ?? this.showSearch,
      showTapConfirm:         showTapConfirm         ?? this.showTapConfirm,
      userIsExploring:        userIsExploring        ?? this.userIsExploring,
      isSatellite:            isSatellite            ?? this.isSatellite,
      gasolinerasVisible:     gasolinerasVisible     ?? this.gasolinerasVisible,
      gasolinerasLoading:     gasolinerasLoading     ?? this.gasolinerasLoading,
      isRecalculating:        isRecalculating        ?? this.isRecalculating,
      searchLoading:          searchLoading          ?? this.searchLoading,
      isProgrammaticMove:     isProgrammaticMove     ?? this.isProgrammaticMove,
      initialLocationSet:     initialLocationSet     ?? this.initialLocationSet,
      routeDistance:          routeDistance          ?? this.routeDistance,
      routeDuration:          routeDuration          ?? this.routeDuration,
      currentInstruction:     currentInstruction     ?? this.currentInstruction,
      distanceToNextManeuver: distanceToNextManeuver ?? this.distanceToNextManeuver,
      tappedLat:              clearTappedLat         ? null : tappedLat        ?? this.tappedLat,
      tappedLng:              clearTappedLng         ? null : tappedLng        ?? this.tappedLng,
      currentStepIndex:       currentStepIndex       ?? this.currentStepIndex,
      selectedRouteIndex:     selectedRouteIndex     ?? this.selectedRouteIndex,
      currentTabIndex:        currentTabIndex        ?? this.currentTabIndex,
      searchResults:          searchResults          ?? this.searchResults,
      alternateRoutes:        alternateRoutes        ?? this.alternateRoutes,
      routeSteps:             routeSteps             ?? this.routeSteps,
      routeCoordinates:       routeCoordinates       ?? this.routeCoordinates,
      trips:                  trips                  ?? this.trips,
      selectedPlace:          clearSelectedPlace     ? null : selectedPlace    ?? this.selectedPlace,
      userAvatarImage:        userAvatarImage        ?? this.userAvatarImage,
      pinImage:               pinImage               ?? this.pinImage,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────
class MapNotifier extends Notifier<MapState> {
  @override
  MapState build() => const MapState();

  void update(MapState Function(MapState s) updater) {
    state = updater(state);
  }

  // ── Shortcuts comunes ─────────────────────────────────
  void setSpeed(double speed)             => state = state.copyWith(currentSpeed: speed);
  void setPosition(Position position)     => state = state.copyWith(currentPosition: position);
  void setNavigating(bool v)              => state = state.copyWith(navigating: v);
  void setRouteDrawn(bool v)              => state = state.copyWith(routeDrawn: v);
  void setShowSearch(bool v)              => state = state.copyWith(showSearch: v);
  void setUserIsExploring(bool v)         => state = state.copyWith(userIsExploring: v);
  void setSatellite(bool v)               => state = state.copyWith(isSatellite: v);
  void setGasolinerasVisible(bool v)      => state = state.copyWith(gasolinerasVisible: v);
  void setGasolinerasLoading(bool v)      => state = state.copyWith(gasolinerasLoading: v);
  void setIsRecalculating(bool v)         => state = state.copyWith(isRecalculating: v);
  void setSearchLoading(bool v)           => state = state.copyWith(searchLoading: v);
  void setIsProgrammaticMove(bool v)      => state = state.copyWith(isProgrammaticMove: v);
  void setInitialLocationSet(bool v)      => state = state.copyWith(initialLocationSet: v);
  void setTabIndex(int i)                 => state = state.copyWith(currentTabIndex: i);
  void setSearchResults(List<Map<String,dynamic>> r) => state = state.copyWith(searchResults: r);
  void setTrips(List<TripRecord> t)       => state = state.copyWith(trips: t);
  void setUserAvatar(Uint8List? img)      => state = state.copyWith(userAvatarImage: img);
  void setPinImage(Uint8List img)         => state = state.copyWith(pinImage: img);

  void setTappedLocation(double lat, double lng) => state = state.copyWith(
    showTapConfirm: true, tappedLat: lat, tappedLng: lng,
  );

  void clearTap() => state = state.copyWith(
    showTapConfirm: false,
    clearTappedLat: true,
    clearTappedLng: true,
  );

  void clearSearch() => state = state.copyWith(
    showSearch: false, searchResults: const [],
  );

  void setRouteData({
    required String distance,
    required String duration,
    required List<List<double>> coords,
    required List<Map<String,dynamic>> steps,
    required List<Map<String,dynamic>> alternates,
  }) {
    state = state.copyWith(
      routeDrawn:             true,
      routeDistance:          distance,
      routeDuration:          duration,
      routeCoordinates:       coords,
      routeSteps:             steps,
      alternateRoutes:        alternates,
      selectedRouteIndex:     0,
      currentStepIndex:       0,
      currentInstruction:     steps.isNotEmpty
          ? steps[0]['instruction'] as String : '',
      distanceToNextManeuver: steps.isNotEmpty
          ? steps[0]['distance'] as double : 0.0,
    );
  }

  void selectRoute(int i, List<Map<String,dynamic>> alternates) {
    final r     = alternates[i];
    final steps = List<Map<String,dynamic>>.from(r['steps']);
    state = state.copyWith(
      selectedRouteIndex:     i,
      routeDistance:          r['distance'],
      routeDuration:          r['duration'],
      routeCoordinates:       List<List<double>>.from(r['coords']),
      routeSteps:             steps,
      currentStepIndex:       0,
      currentInstruction:     steps.isNotEmpty
          ? steps[0]['instruction'] as String : '',
      distanceToNextManeuver: steps.isNotEmpty
          ? steps[0]['distance'] as double : 0.0,
    );
  }

  void clearRoute() {
    state = state.copyWith(
      routeDrawn:             false,
      navigating:             false,
      showTapConfirm:         false,
      routeDistance:          '',
      routeDuration:          '',
      routeCoordinates:       const [],
      alternateRoutes:        const [],
      routeSteps:             const [],
      currentInstruction:     '',
      currentStepIndex:       0,
      distanceToNextManeuver: 0.0,
      selectedRouteIndex:     0,
      clearSelectedPlace:     true,
      clearTappedLat:         true,
      clearTappedLng:         true,
    );
  }

  void updateTurn({
    required double distance,
    required int stepIndex,
    required String instruction,
  }) {
    state = state.copyWith(
      distanceToNextManeuver: distance,
      currentStepIndex:       stepIndex,
      currentInstruction:     instruction,
    );
  }
}

// ── Provider global ───────────────────────────────────────
final mapProvider = NotifierProvider<MapNotifier, MapState>(
  MapNotifier.new,
);
