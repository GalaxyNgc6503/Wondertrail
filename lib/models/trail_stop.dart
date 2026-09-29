import 'dart:io';
import 'package:latlong2/latlong.dart';

/// Fixed category set used for both a stop's single category and a trail's
/// multi-select category tags — kept as one shared list so the two stay
/// in sync (e.g. a trail's category filter chips reflect real stop values).
const List<String> kCategories = ['Culture', 'Food', 'View', 'Nature'];

enum TrailVisibility {
  public,
  private;

  String get label => this == TrailVisibility.public ? 'Public' : 'Private';
  String get storageValue => name;

  static TrailVisibility fromStorageValue(String? value) {
    return TrailVisibility.values.firstWhere(
      (v) => v.storageValue == value,
      orElse: () => TrailVisibility.public,
    );
  }
}

/// A single stop within a trail being built.
class TrailStop {
  TrailStop({
    required this.id,
    required this.name,
    required this.note,
    required this.location,
    this.photos = const [],
    this.photoFileIds,
    this.category,
    this.recommendedTimeMinutes,
    this.estimatedCost,
    this.tips,
    this.crossTrailAvailable = true,
  });

  final String id;
  final String name;

  /// Short "why visit" description — spec calls this the stop's Description.
  final String note;
  final LatLng location;
  final List<File> photos;

  /// Set once the photos have been uploaded to Appwrite Storage, in the
  /// same order as [photos]. The first entry is used as this stop's
  /// thumbnail and, for the trail's first stop, as the trail cover fallback.
  final List<String>? photoFileIds;

  /// One of [kCategories], or null if unset.
  final String? category;

  /// Roughly how long a Traveller should expect to spend here.
  final int? recommendedTimeMinutes;

  /// Free-text so Explorers can write "Free", "RM10–20", "$5", etc. — not
  /// parsed or aggregated anywhere; see the Publish step for why.
  final String? estimatedCost;

  /// Traveller-facing tips ("go at sunset", "cash only", etc).
  final String? tips;

  /// Whether a Traveller on a *different* trail can roll into this stop —
  /// the mechanic behind cross-trail discovery. Defaults on, matching the
  /// spec's example screen.
  final bool crossTrailAvailable;

  TrailStop copyWith({
    String? name,
    String? note,
    List<File>? photos,
    List<String>? photoFileIds,
    String? category,
    int? recommendedTimeMinutes,
    String? estimatedCost,
    String? tips,
    bool? crossTrailAvailable,
  }) {
    return TrailStop(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      location: location,
      photos: photos ?? this.photos,
      photoFileIds: photoFileIds ?? this.photoFileIds,
      category: category ?? this.category,
      recommendedTimeMinutes: recommendedTimeMinutes ?? this.recommendedTimeMinutes,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      tips: tips ?? this.tips,
      crossTrailAvailable: crossTrailAvailable ?? this.crossTrailAvailable,
    );
  }
}

/// A published (or in-progress) trail.
class Trail {
  Trail({
    required this.title,
    required this.stops,
    this.id,
    this.description = '',
    this.startingLocationLabel,
    this.startingLocation,
    this.coverPhoto,
    this.coverPhotoFileId,
    this.crossTrailDiscovery = false,
    this.nearbyRadiusKm = 2,
    this.categories = const [],
    this.visibility = TrailVisibility.public,
  });

  final String title;
  final List<TrailStop> stops;

  /// Set once the trail document has been created in Appwrite.
  final String? id;

  final String description;
  final String? startingLocationLabel;
  final LatLng? startingLocation;

  /// Local file picked in the wizard, pre-publish. Not sent to Appwrite
  /// directly — [TrailRepository.publishTrail] uploads it and stores the
  /// resulting [coverPhotoFileId] instead.
  final File? coverPhoto;

  /// Set once the cover photo has been uploaded (or resolved from the
  /// first stop's first photo as a fallback).
  final String? coverPhotoFileId;

  // Note: how stops are served during a roll (in order / random / traveller
  // picks) is intentionally NOT here. It's a Traveller-time preference, not
  // something the Explorer locks in at publish time — see the README.
  final bool crossTrailDiscovery;
  final double nearbyRadiusKm;
  final List<String> categories;
  final TrailVisibility visibility;

  Trail copyWith({
    String? id,
    List<TrailStop>? stops,
    String? description,
    String? startingLocationLabel,
    LatLng? startingLocation,
    File? coverPhoto,
    String? coverPhotoFileId,
    bool? crossTrailDiscovery,
    double? nearbyRadiusKm,
    List<String>? categories,
    TrailVisibility? visibility,
  }) {
    return Trail(
      title: title,
      stops: stops ?? this.stops,
      id: id ?? this.id,
      description: description ?? this.description,
      startingLocationLabel: startingLocationLabel ?? this.startingLocationLabel,
      startingLocation: startingLocation ?? this.startingLocation,
      coverPhoto: coverPhoto ?? this.coverPhoto,
      coverPhotoFileId: coverPhotoFileId ?? this.coverPhotoFileId,
      crossTrailDiscovery: crossTrailDiscovery ?? this.crossTrailDiscovery,
      nearbyRadiusKm: nearbyRadiusKm ?? this.nearbyRadiusKm,
      categories: categories ?? this.categories,
      visibility: visibility ?? this.visibility,
    );
  }

  /// Rough walking distance estimate for the demo — replace with a real
  /// routing-API call (e.g. OSRM) once there's a backend to hit.
  double get roughDistanceKm => stops.length * 0.6;

  /// Sum of each stop's recommended time, for stops that set one. Returns
  /// null (rather than a misleadingly-low number) if none did.
  int? get totalRecommendedMinutes {
    final withTime = stops.where((s) => s.recommendedTimeMinutes != null);
    if (withTime.isEmpty) return null;
    return withTime.fold<int>(0, (sum, s) => sum + s.recommendedTimeMinutes!);
  }
}

/// A lightweight view of a trail for list screens (Explore) — just the
/// "trails" document fields, no stops. Denormalized on purpose (stopCount,
/// coverPhotoFileId live directly on the trail document) so rendering a
/// list of cards takes one query, not one query per trail's stops.
class TrailSummary {
  const TrailSummary({
    required this.id,
    required this.title,
    required this.authorId,
    required this.stopCount,
    required this.distanceKm,
    this.coverPhotoFileId,
    this.categories = const [],
    this.crossTrailDiscovery = false,
  });

  final String id;
  final String title;
  final String authorId;
  final int stopCount;
  final double distanceKm;
  final String? coverPhotoFileId;
  final List<String> categories;
  final bool crossTrailDiscovery;

  factory TrailSummary.fromDocument(String id, Map<String, dynamic> data) {
    return TrailSummary(
      id: id,
      title: data['title'] as String? ?? 'Untitled trail',
      authorId: data['authorId'] as String? ?? 'unknown',
      stopCount: (data['stopCount'] as num?)?.toInt() ?? 0,
      distanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 0,
      coverPhotoFileId: data['coverPhotoFileId'] as String?,
      categories: (data['categories'] as List<dynamic>?)?.cast<String>() ?? const [],
      crossTrailDiscovery: data['crossTrailDiscovery'] as bool? ?? false,
    );
  }
}
