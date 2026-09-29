import 'package:appwrite/appwrite.dart';
import 'package:latlong2/latlong.dart';

import '../models/trail_stop.dart';
import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'photo_urls.dart';

/// Thrown when publishing fails, wrapping whatever Appwrite reported.
class TrailPublishException implements Exception {
  TrailPublishException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when fetching trails fails, wrapping whatever Appwrite reported.
class TrailLoadException implements Exception {
  TrailLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TrailRepository {
  TrailRepository({Databases? databases, Storage? storage})
      : _databases = databases ?? AppwriteService.databases,
        _storage = storage ?? AppwriteService.storage;

  final Databases _databases;
  final Storage _storage;

  /// Uploads any local stop photos to Storage, creates a "stops" document
  /// per stop, then creates the "trails" document referencing them.
  /// [coverPhoto] on the trail, if set, is uploaded separately and used as
  /// the trail's cover instead of falling back to the first stop's photo.
  /// Returns the published [Trail] with server-assigned ids filled in.
  Future<Trail> publishTrail(Trail trail, {required String authorId}) async {
    try {
      final uploadedStops = <TrailStop>[];

      for (final stop in trail.stops) {
        final photoFileIds = <String>[];

        for (final photo in stop.photos) {
          final uploaded = await _storage.createFile(
            bucketId: AppwriteConfig.photosBucketId,
            fileId: ID.unique(),
            file: InputFile.fromPath(path: photo.path),
          );
          photoFileIds.add(uploaded.$id);
        }

        uploadedStops.add(stop.copyWith(photoFileIds: photoFileIds));
      }

      String? coverPhotoFileId;
      if (trail.coverPhoto != null) {
        final uploaded = await _storage.createFile(
          bucketId: AppwriteConfig.photosBucketId,
          fileId: ID.unique(),
          file: InputFile.fromPath(path: trail.coverPhoto!.path),
        );
        coverPhotoFileId = uploaded.$id;
      } else if (uploadedStops.isNotEmpty && (uploadedStops.first.photoFileIds?.isNotEmpty ?? false)) {
        coverPhotoFileId = uploadedStops.first.photoFileIds!.first;
      }

      final trailDoc = await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.trailsCollectionId,
        documentId: ID.unique(),
        data: {
          'title': trail.title,
          'description': trail.description,
          'authorId': authorId,
          'stopCount': uploadedStops.length,
          'distanceKm': trail.roughDistanceKm,
          'coverPhotoFileId': coverPhotoFileId,
          'startingLocationLabel': trail.startingLocationLabel,
          'startingLat': trail.startingLocation?.latitude,
          'startingLng': trail.startingLocation?.longitude,
          'crossTrailDiscovery': trail.crossTrailDiscovery,
          'nearbyRadiusKm': trail.nearbyRadiusKm,
          'categories': trail.categories,
          'visibility': trail.visibility.storageValue,
        },
      );

      for (var i = 0; i < uploadedStops.length; i++) {
        final stop = uploadedStops[i];
        await _databases.createDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.stopsCollectionId,
          documentId: ID.unique(),
          data: {
            'trailId': trailDoc.$id,
            'order': i,
            'name': stop.name,
            'note': stop.note,
            'lat': stop.location.latitude,
            'lng': stop.location.longitude,
            'photoFileIds': stop.photoFileIds ?? const [],
            'category': stop.category,
            'recommendedTimeMinutes': stop.recommendedTimeMinutes,
            'estimatedCost': stop.estimatedCost,
            'tips': stop.tips,
            'crossTrailAvailable': stop.crossTrailAvailable,
          },
        );
      }

      return trail.copyWith(id: trailDoc.$id, stops: uploadedStops, coverPhotoFileId: coverPhotoFileId);
    } on AppwriteException catch (e) {
      throw TrailPublishException(e.message ?? 'Failed to publish trail.');
    }
  }

  /// Fetches a single trail's document plus its stops, ordered by `order`
  /// — this is what a trail detail screen needs (Explore's list only reads
  /// the summary fields, not this).
  Future<Trail> getTrail(String trailId) async {
    try {
      final trailDoc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.trailsCollectionId,
        documentId: trailId,
      );

      final stopsResult = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.stopsCollectionId,
        queries: [Query.equal('trailId', trailId), Query.orderAsc('order')],
      );

      final stops = stopsResult.documents.map((doc) {
        final data = doc.data;
        return TrailStop(
          id: doc.$id,
          name: data['name'] as String? ?? '',
          note: data['note'] as String? ?? '',
          location: LatLng(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
          ),
          photoFileIds: (data['photoFileIds'] as List<dynamic>?)?.cast<String>() ?? const [],
          category: data['category'] as String?,
          recommendedTimeMinutes: (data['recommendedTimeMinutes'] as num?)?.toInt(),
          estimatedCost: data['estimatedCost'] as String?,
          tips: data['tips'] as String?,
          crossTrailAvailable: data['crossTrailAvailable'] as bool? ?? true,
        );
      }).toList();

      final data = trailDoc.data;
      final startingLat = data['startingLat'] as num?;
      final startingLng = data['startingLng'] as num?;

      return Trail(
        id: trailDoc.$id,
        title: data['title'] as String? ?? 'Untitled trail',
        description: data['description'] as String? ?? '',
        stops: stops,
        startingLocationLabel: data['startingLocationLabel'] as String?,
        startingLocation: (startingLat != null && startingLng != null)
            ? LatLng(startingLat.toDouble(), startingLng.toDouble())
            : null,
        coverPhotoFileId: data['coverPhotoFileId'] as String?,
        crossTrailDiscovery: data['crossTrailDiscovery'] as bool? ?? false,
        nearbyRadiusKm: (data['nearbyRadiusKm'] as num?)?.toDouble() ?? 2,
        categories: (data['categories'] as List<dynamic>?)?.cast<String>() ?? const [],
        visibility: TrailVisibility.fromStorageValue(data['visibility'] as String?),
      );
    } on AppwriteException catch (e) {
      throw TrailLoadException(e.message ?? 'Failed to load trail.');
    }
  }

  /// Fetches published trails for the Explore feed, newest first. Only
  /// reads the "trails" documents — not each trail's stops — since the
  /// card view only needs the denormalized summary fields.
  Future<List<TrailSummary>> listTrails({int limit = 25}) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.trailsCollectionId,
        queries: [Query.orderDesc('\$createdAt'), Query.limit(limit)],
      );
      return result.documents
          .map((doc) => TrailSummary.fromDocument(doc.$id, doc.data))
          .toList();
    } on AppwriteException catch (e) {
      throw TrailLoadException(e.message ?? 'Failed to load trails.');
    }
  }

  /// Convenience getters for rendering an uploaded photo — see [PhotoUrls].
  String photoUrl(String fileId) => PhotoUrls.view(fileId);
  String previewUrl(String fileId, {int width = 400}) => PhotoUrls.preview(fileId, width: width);
}
