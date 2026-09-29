import 'package:appwrite/appwrite.dart';

import '../models/destination.dart';
import 'appwrite_config.dart';
import 'appwrite_service.dart';

/// Thrown when a destination read/write fails, wrapping Appwrite's message.
class DestinationException implements Exception {
  DestinationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads and writes the `destinations` collection.
///
/// Ownership is enforced client-side ([Destination.isMine]) because this
/// repo has no auth yet. Once real auth exists, turn on document-level
/// security and grant update/delete to `Role.user(authorId)` so the server
/// enforces it too — see the README.
class DestinationRepository {
  DestinationRepository({Databases? databases, Storage? storage})
      : _databases = databases ?? AppwriteService.databases,
        _storage = storage ?? AppwriteService.storage;

  final Databases _databases;
  final Storage _storage;

  static const _pageSize = 100;
  static const _maxPages = 3;

  /// Turns any failure into a [DestinationException] with a short, readable
  /// message — never propagates the raw error. Appwrite SDK calls can throw
  /// things other than [AppwriteException] (a network error, or — commonly
  /// when `APPWRITE_ENDPOINT` in `.env` is wrong — an HTML error page from
  /// hitting the console URL instead of the API), and letting those escape
  /// as unhandled exceptions used to dump a multi-KB HTML blob straight to
  /// the console instead of telling you what to fix.
  Never _throwFriendly(Object error, String action) {
    final message = error is AppwriteException ? (error.message ?? '') : error.toString();
    final trimmed = message.trimLeft();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html') || trimmed.startsWith('<?xml')) {
      throw DestinationException(
        "$action Appwrite returned a webpage instead of API data — check "
        "APPWRITE_ENDPOINT in your .env: it must be your project's API "
        "endpoint (ends in /v1, e.g. https://fra.cloud.appwrite.io/v1), "
        "not the console URL.",
      );
    }
    if (error is AppwriteException) {
      throw DestinationException(message.isEmpty ? action : message);
    }
    final summary = message.length > 160 ? '${message.substring(0, 160)}…' : message;
    throw DestinationException('$action ($summary)');
  }

  /// Every destination inside the given box (needs indexes on `lat`, `lng`).
  Future<List<Destination>> listInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    try {
      final all = <Destination>[];
      for (var page = 0; page < _maxPages; page++) {
        final result = await _databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.destinationsCollectionId,
          queries: [
            Query.between('lat', south, north),
            Query.between('lng', west, east),
            Query.limit(_pageSize),
            Query.offset(page * _pageSize),
          ],
        );
        all.addAll(result.documents.map((d) => Destination.fromMap(d.$id, d.data)));
        if (result.documents.length < _pageSize) break;
      }
      return all;
    } catch (e) {
      _throwFriendly(e, 'Failed to load destinations.');
    }
  }

  /// Destinations a user added, wherever they are (needs an `authorId` index).
  Future<List<Destination>> listByAuthor(String authorId) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.destinationsCollectionId,
        queries: [
          Query.equal('authorId', authorId),
          Query.equal('source', DestinationSource.community.storageValue),
          Query.orderDesc('\$createdAt'),
          Query.limit(_pageSize),
        ],
      );
      return result.documents.map((d) => Destination.fromMap(d.$id, d.data)).toList();
    } catch (e) {
      _throwFriendly(e, 'Failed to load your destinations.');
    }
  }

  /// Uploads [draft]'s local photo and creates the document.
  Future<Destination> create(Destination draft, {required String authorId}) async {
    try {
      final photoFileId = draft.localPhoto != null
          ? await _uploadPhoto(draft.localPhoto!.path)
          : draft.photoFileId;

      final toSave = Destination(
        id: '',
        name: draft.name,
        description: draft.description,
        category: draft.category,
        visitMinutes: draft.visitMinutes,
        cost: draft.cost,
        location: draft.location,
        tips: draft.tips,
        photoFileId: photoFileId,
        authorId: authorId,
        source: DestinationSource.community,
      );

      final doc = await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.destinationsCollectionId,
        documentId: ID.unique(),
        data: toSave.toMap(),
      );
      return Destination.fromMap(doc.$id, doc.data);
    } catch (e) {
      _throwFriendly(e, 'Failed to publish destination.');
    }
  }

  /// Saves edits to a destination the user owns. If [edited] carries a new
  /// local photo it's uploaded and the previous file is removed.
  Future<Destination> update(Destination edited, {required String userId}) async {
    if (!edited.isMine(userId)) {
      throw DestinationException('You can only edit destinations you added.');
    }
    try {
      var photoFileId = edited.photoFileId;
      String? replacedFileId;
      if (edited.localPhoto != null) {
        replacedFileId = edited.photoFileId;
        photoFileId = await _uploadPhoto(edited.localPhoto!.path);
      }

      final toSave = edited.copyWith(photoFileId: photoFileId);
      final doc = await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.destinationsCollectionId,
        documentId: edited.id,
        data: toSave.toMap(),
      );

      if (replacedFileId != null) await _deletePhotoQuietly(replacedFileId);
      return Destination.fromMap(doc.$id, doc.data);
    } catch (e) {
      _throwFriendly(e, 'Failed to save changes.');
    }
  }

  Future<void> delete(Destination destination, {required String userId}) async {
    if (!destination.isMine(userId)) {
      throw DestinationException('You can only delete destinations you added.');
    }
    try {
      await _databases.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.destinationsCollectionId,
        documentId: destination.id,
      );
      if (destination.photoFileId != null) await _deletePhotoQuietly(destination.photoFileId!);
    } catch (e) {
      _throwFriendly(e, 'Failed to delete destination.');
    }
  }

  Future<String> _uploadPhoto(String path) async {
    final file = await _storage.createFile(
      bucketId: AppwriteConfig.photosBucketId,
      fileId: ID.unique(),
      file: InputFile.fromPath(path: path),
    );
    return file.$id;
  }

  /// A leftover photo isn't worth failing the whole operation over.
  Future<void> _deletePhotoQuietly(String fileId) async {
    try {
      await _storage.deleteFile(bucketId: AppwriteConfig.photosBucketId, fileId: fileId);
    } catch (_) {
      // ignore — any failure (Appwrite or otherwise) is fine to swallow here
    }
  }
}
