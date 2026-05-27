import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import '../../data/models/trip_record.dart';

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
  final bool isNightMode;
  final bool nightModeManual;
  final int? speedLimit;
  final List<Map<String, dynamic>> waypoints;
  final bool isSelectingWaypoints;
  final bool showWaypointArrival;
  final String waypointArrivalMessage;
  final int currentWaypointIndex;

  const MapState({
    this.currentSpeed = 0.0,
    this.currentPosition,
    this.navigating = false,
    this.routeDrawn = false,
    this.showSearch = false,
    this.showTapConfirm = false,
    this.userIsExploring = false,
    this.isSatellite = false,
    this.gasolinerasVisible = false,
    this.gasolinerasLoading = false,
    this.isRecalculating = false,
    this.searchLoading = false,
    this.isProgrammaticMove = false,
    this.initialLocationSet = false,
    this.routeDistance = '',
    this.routeDuration = '',
    this.currentInstruction = '',
    this.distanceToNextManeuver = 0.0,
    this.tappedLat,
    this.tappedLng,
    this.currentStepIndex = 0,
    this.selectedRouteIndex = 0,
    this.currentTabIndex = 0,
    this.searchResults = const [],
    this.alternateRoutes = const [],
    this.routeSteps = const [],
    this.routeCoordinates = const [],
    this.trips = const [],
    this.selectedPlace,
    this.userAvatarImage,
    this.pinImage,
    this.isNightMode = false,
    this.nightModeManual = false,
    this.speedLimit,
    this.waypoints = const [],
    this.isSelectingWaypoints = false,
    this.showWaypointArrival = false,
    this.waypointArrivalMessage = '',
    this.currentWaypointIndex = 0,
  });

  MapState copyWith({
    double? currentSpeed,
    Position? currentPosition,
    bool? navigating,
    bool? routeDrawn,
    bool? showSearch,
    bool? showTapConfirm,
    bool? userIsExploring,
    bool? isSatellite,
    bool? gasolinerasVisible,
    bool? gasolinerasLoading,
    bool? isRecalculating,
    bool? searchLoading,
    bool? isProgrammaticMove,
    bool? initialLocationSet,
    String? routeDistance,
    String? routeDuration,
    String? currentInstruction,
    double? distanceToNextManeuver,
    double? tappedLat,
    double? tappedLng,
    int? currentStepIndex,
    int? selectedRouteIndex,
    int? currentTabIndex,
    List<Map<String, dynamic>>? searchResults,
    List<Map<String, dynamic>>? alternateRoutes,
    List<Map<String, dynamic>>? routeSteps,
    List<List<double>>? routeCoordinates,
    List<TripRecord>? trips,
    Map<String, dynamic>? selectedPlace,
    Uint8List? userAvatarImage,
    Uint8List? pinImage,
    bool? isNightMode,
    bool? nightModeManual,
    int? speedLimit,
    List<Map<String, dynamic>>? waypoints,
    bool? isSelectingWaypoints,
    bool? showWaypointArrival,
    String? waypointArrivalMessage,
    int? currentWaypointIndex,
    bool clearCurrentPosition = false,
    bool clearSelectedPlace = false,
    bool clearTappedLat = false,
    bool clearTappedLng = false,
    bool clearSpeedLimit = false,
  }) {
    return MapState(
      currentSpeed: currentSpeed ?? this.currentSpeed,
      currentPosition: clearCurrentPosition ? null : currentPosition ?? this.currentPosition,
      navigating: navigating ?? this.navigating,
      routeDrawn: routeDrawn ?? this.routeDrawn,
      showSearch: showSearch ?? this.showSearch,
      showTapConfirm: showTapConfirm ?? this.showTapConfirm,
      userIsExploring: userIsExploring ?? this.userIsExploring,
      isSatellite: isSatellite ?? this.isSatellite,
      gasolinerasVisible: gasolinerasVisible ?? this.gasolinerasVisible,
      gasolinerasLoading: gasolinerasLoading ?? this.gasolinerasLoading,
      isRecalculating: isRecalculating ?? this.isRecalculating,
      searchLoading: searchLoading ?? this.searchLoading,
      isProgrammaticMove: isProgrammaticMove ?? this.isProgrammaticMove,
      initialLocationSet: initialLocationSet ?? this.initialLocationSet,
      routeDistance: routeDistance ?? this.routeDistance,
      routeDuration: routeDuration ?? this.routeDuration,
      currentInstruction: currentInstruction ?? this.currentInstruction,
      distanceToNextManeuver: distanceToNextManeuver ?? this.distanceToNextManeuver,
      tappedLat: clearTappedLat ? null : tappedLat ?? this.tappedLat,
      tappedLng: clearTappedLng ? null : tappedLng ?? this.tappedLng,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      selectedRouteIndex: selectedRouteIndex ?? this.selectedRouteIndex,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      searchResults: searchResults ?? this.searchResults,
      alternateRoutes: alternateRoutes ?? this.alternateRoutes,
      routeSteps: routeSteps ?? this.routeSteps,
      routeCoordinates: routeCoordinates ?? this.routeCoordinates,
      trips: trips ?? this.trips,
      selectedPlace: clearSelectedPlace ? null : selectedPlace ?? this.selectedPlace,
      userAvatarImage: userAvatarImage ?? this.userAvatarImage,
      pinImage: pinImage ?? this.pinImage,
      isNightMode: isNightMode ?? this.isNightMode,
      nightModeManual: nightModeManual ?? this.nightModeManual,
      speedLimit: clearSpeedLimit ? null : speedLimit ?? this.speedLimit,
      waypoints: waypoints ?? this.waypoints,
      isSelectingWaypoints: isSelectingWaypoints ?? this.isSelectingWaypoints,
      showWaypointArrival: showWaypointArrival ?? this.showWaypointArrival,
      waypointArrivalMessage: waypointArrivalMessage ?? this.waypointArrivalMessage,
      currentWaypointIndex: currentWaypointIndex ?? this.currentWaypointIndex,
    );
  }
}
