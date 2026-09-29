import 'dart:io';

import 'package:latlong2/latlong.dart';

import 'trail_stop.dart' show kCategories;

/// Where a destination came from. Drives how it's drawn on the map and
/// whether anyone can edit it.
enum DestinationSource {
  /// Part of the base dataset — not editable in the app.
  curated,

  /// Contributed by a user through the Build page.
  community;

  String get storageValue => name;

  static DestinationSource fromStorageValue(String? value) {
    return DestinationSource.values.firstWhere(
      (s) => s.name == value,
      orElse: () => DestinationSource.curated,
    );
  }
}

/// A single place on the map that can be rolled into a trail.
class Destination {
  const Destination({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.visitMinutes,
    required this.cost,
    required this.location,
    this.tips,
    this.photoFileId,
    this.localPhoto,
    this.authorId = '',
    this.source = DestinationSource.community,
  });

  final String id;
  final String name;
  final String description;

  /// One of [kCategories].
  final String category;

  /// Estimated time a visitor spends here.
  final int visitMinutes;

  /// Free text ("Free", "RM10–20") — shown as written, never parsed.
  final String cost;
  final LatLng location;
  final String? tips;

  /// Uploaded photo (Appwrite Storage file id).
  final String? photoFileId;

  /// Photo picked on this device but not uploaded yet. Only used by the
  /// form and its preview — never persisted.
  final File? localPhoto;

  final String authorId;
  final DestinationSource source;

  bool get isCommunity => source == DestinationSource.community;

  /// True only for destinations the given user added — the only ones they
  /// may edit or delete.
  bool isMine(String userId) => isCommunity && authorId == userId;

  String get visitLabel => formatMinutes(visitMinutes);

  Destination copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    int? visitMinutes,
    String? cost,
    LatLng? location,
    String? tips,
    String? photoFileId,
    File? localPhoto,
    String? authorId,
    DestinationSource? source,
  }) {
    return Destination(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      visitMinutes: visitMinutes ?? this.visitMinutes,
      cost: cost ?? this.cost,
      location: location ?? this.location,
      tips: tips ?? this.tips,
      photoFileId: photoFileId ?? this.photoFileId,
      localPhoto: localPhoto ?? this.localPhoto,
      authorId: authorId ?? this.authorId,
      source: source ?? this.source,
    );
  }

  factory Destination.fromMap(String id, Map<String, dynamic> data) {
    final tips = data['tips'] as String?;
    return Destination(
      id: id,
      name: data['name'] as String? ?? 'Unnamed place',
      description: data['description'] as String? ?? '',
      category: data['category'] as String? ?? kCategories.first,
      visitMinutes: (data['visitMinutes'] as num?)?.toInt() ?? 30,
      cost: data['cost'] as String? ?? 'Free',
      location: LatLng(
        (data['lat'] as num).toDouble(),
        (data['lng'] as num).toDouble(),
      ),
      tips: (tips == null || tips.trim().isEmpty) ? null : tips,
      photoFileId: data['photoFileId'] as String?,
      authorId: data['authorId'] as String? ?? '',
      source: DestinationSource.fromStorageValue(data['source'] as String?),
    );
  }

  /// Document body for Appwrite (no id, no local photo).
  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'category': category,
        'visitMinutes': visitMinutes,
        'cost': cost,
        'tips': tips,
        'lat': location.latitude,
        'lng': location.longitude,
        'photoFileId': photoFileId,
        'authorId': authorId,
        'source': source.storageValue,
      };
}

String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String formatDistance(double meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
