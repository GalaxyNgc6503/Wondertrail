import 'appwrite_config.dart';

/// Builds Appwrite Storage URLs for uploaded photos.
///
/// Built by hand rather than via `Storage.getFileView()` because the Flutter
/// SDK's version of that method returns raw bytes, not a URL. Works with
/// `Image.network()` as long as the bucket's read permission is `Any`.
class PhotoUrls {
  PhotoUrls._();

  static String view(String fileId) => _url(fileId, 'view');

  /// Server-side resized — use for thumbnails and cards.
  static String preview(String fileId, {int width = 600}) =>
      _url(fileId, 'preview', {'width': '$width'});

  static String _url(String fileId, String endpoint, [Map<String, String>? extra]) {
    final base = Uri.parse(AppwriteConfig.endpoint);
    return base.replace(
      path: '${base.path}/storage/buckets/${AppwriteConfig.photosBucketId}/files/$fileId/$endpoint',
      queryParameters: {'project': AppwriteConfig.projectId, ...?extra},
    ).toString();
  }
}
