import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Config values pulled from `.env` (see `.env.example`). Call
/// `await dotenv.load(fileName: ".env")` in `main()` before using these —
/// see the README for the full snippet.
class AppwriteConfig {
  AppwriteConfig._();

  static String get endpoint => dotenv.get('APPWRITE_ENDPOINT');
  static String get projectId => dotenv.get('APPWRITE_PROJECT_ID');
  static String get databaseId => dotenv.get('APPWRITE_DATABASE_ID');
  static String get photosBucketId => dotenv.get('APPWRITE_PHOTOS_BUCKET_ID');

  /// Legacy trail/stop collections — only used by `TrailRepository` and the
  /// `screen/explore/` pages, which aren't wired into the app's bottom nav.
  /// Optional: Roll, Build, and Monetization never touch these, so there's
  /// no need to set them (or create the collections in Appwrite) unless
  /// you're using Explore.
  static String get trailsCollectionId => dotenv.maybeGet('APPWRITE_TRAILS_COLLECTION_ID') ?? 'trails';
  static String get stopsCollectionId => dotenv.maybeGet('APPWRITE_STOPS_COLLECTION_ID') ?? 'stops';

  /// Standalone map destinations (see `DestinationRepository`). Falls back to
  /// `destinations` so existing `.env` files keep working.
  static String get destinationsCollectionId =>
      dotenv.maybeGet('APPWRITE_DESTINATIONS_COLLECTION_ID') ?? 'destinations';
}
