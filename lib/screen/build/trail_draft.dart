import 'package:image_picker/image_picker.dart';

import '../../models/trail_stop.dart';
import '../../services/geocoding_service.dart';

/// In-progress wizard state for one stop, before it has an Appwrite
/// document or uploaded photos. `build_screen.dart` and `add_stop.dart`
/// both need this type — extracted here, in its own file, rather than one
/// of those two screens importing the other and creating exactly the
/// "wrong direction" circular import called out as a pitfall in the build
/// spec.
class StopDraft {
  StopDraft({String? id})
      : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  /// Local-only identifier so the Stops step can find/replace/remove this
  /// draft in its list. Never sent to Appwrite — the real document id is
  /// assigned at publish time.
  final String id;

  String name = '';
  String note = '';

  String locationLabel = '';
  double? lat;
  double? lng;

  List<XFile> photos = <XFile>[];

  String category = kCategories.first;
  int? recommendedTimeMinutes;
  String? estimatedCost;
  String? tips;

  /// "🎲 Available for cross-trail rolls" — on by default.
  bool crossTrailAvailable = true;

  bool get hasLocation => lat != null && lng != null;

  bool get isReadyToSave => name.trim().isNotEmpty && hasLocation;

  StopDraft copy() {
    return StopDraft(id: id)
      ..name = name
      ..note = note
      ..locationLabel = locationLabel
      ..lat = lat
      ..lng = lng
      ..photos = List<XFile>.from(photos)
      ..category = category
      ..recommendedTimeMinutes = recommendedTimeMinutes
      ..estimatedCost = estimatedCost
      ..tips = tips
      ..crossTrailAvailable = crossTrailAvailable;
  }
}

/// In-progress wizard state for the whole trail being published.
class TrailDraft {
  String title = '';
  GeocodingResult? startingLocation;
  XFile? coverPhoto;
  String description = '';

  List<StopDraft> stops = <StopDraft>[];

  /// Every published trail is public and open to cross-trail discovery —
  /// no per-trail opt-out. Those aren't draft fields the wizard lets you
  /// change; they're hardcoded at the publish call in build_screen.dart.
  double nearbyRadiusKm = 2.0;
  List<String> categories = <String>[];

  bool get canLeaveBasics =>
      title.trim().isNotEmpty && startingLocation != null;

  bool get canLeaveStops => stops.length >= 2;

  int? get totalTimeMinutes {
    if (stops.isEmpty) return null;
    final bool anySet = stops.any((StopDraft s) => s.recommendedTimeMinutes != null);
    if (!anySet) return null;
    return stops.fold<int>(
      0,
      (int sum, StopDraft s) => sum + (s.recommendedTimeMinutes ?? 0),
    );
  }
}
