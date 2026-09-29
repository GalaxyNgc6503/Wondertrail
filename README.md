# Wondertrail — "Build" tab (Flutter)

A working implementation of the Build tab from the HTML mockup: trail
title, an ordered (drag-to-reorder) stop list, an add-stop flow (location
search → tap-to-drop-pin map → photo/name/note form), and publishing that
actually saves to **Appwrite** — photos to Storage, trail + stops to the
Database.

## Files

```
lib/
  Screen/
    Build/
      build_trail_screen.dart           the Build tab itself
  theme/app_theme.dart                design tokens (colors, text styles)
  models/trail_stop.dart              TrailStop and Trail data classes
  services/appwrite_config.dart       reads .env into typed getters
  services/appwrite_service.dart      shared Client/Databases/Storage
  services/trail_repository.dart      uploads photos + creates documents
  widgets/location_picker_sheet.dart  search bar + OpenStreetMap pin-drop sheet
  widgets/stop_detail_sheet.dart      photo + name + note sheet
.env.example                         copy to .env and fill in your values
pubspec.yaml                        full dependency list, already merged
```

## Setup

1. **Use `pubspec.yaml`** as-is, or diff it against your current one if you've made other changes since.
2. **Copy `.env.example` to `.env`** and fill in your real Appwrite values
   (endpoint, project ID, database ID, the two collection IDs, the storage
   bucket ID). Add `.env` to `.gitignore` — don't commit real credentials.
3. **Register `.env` as an asset** in `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - .env
   ```
4. **Load it before `runApp`** in `main.dart`:
   ```dart
   import 'package:flutter_dotenv/flutter_dotenv.dart';

   Future<void> main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await dotenv.load(fileName: '.env');
     runApp(const MyApp());
   }
   ```
5. **Create the Appwrite resources** the config expects:
   - A **Storage bucket** for photos (its ID → `APPWRITE_PHOTOS_BUCKET_ID`).
   - A **`trails` collection** with attributes: `title` (string),
     `authorId` (string), `stopCount` (integer), `distanceKm` (double),
     `coverPhotoFileId` (string, nullable).
   - A **`stops` collection** with attributes: `trailId` (string),
     `order` (integer), `name` (string), `note` (string), `lat` (double),
     `lng` (double), `photoFileId` (string, nullable).
   - Set collection permissions so authenticated users can create documents
     (this repo doesn't include auth — plug in whatever you're using for
     `authorId`).

## Wiring it into your app

```dart
BuildTrailScreen(
  authorId: currentUser.id, // wherever your auth state lives
  onPublish: (trail) {
    // `trail.id` and each stop's `photoFileId` are now set — prepend
    // `trail` to your Home list, or just re-fetch from Appwrite.
    setState(() => myTrails.insert(0, trail));
  },
)
```

Rendering an uploaded photo elsewhere in the app:

```dart
Image.network(TrailRepository().photoUrl(stop.photoFileId!))
```

## What's real vs. mocked

- **Map** — real, using `flutter_map` with OpenStreetMap tiles. No API key
  required. Tapping the map drops an actual pin at real lat/lng coordinates.
- **Photo picker** — real, using `image_picker`; pulls from the device
  gallery and previews the actual selected image.
- **Appwrite storage + database writes** — real. `TrailRepository.publishTrail`
  uploads each stop's photo to Storage, then creates one `stops` document
  per stop and one `trails` document, in that order, inside a try/catch that
  surfaces failures as a `TrailPublishException` shown inline on the Build
  screen.
- **Location search suggestions** — mocked (`MockPlace.all` in
  `location_picker_sheet.dart`). Swap this for a real geocoding/places
  lookup when you have one — the app description calls for a free-tier
  reverse-geocoding API for this.
- **Distance estimate** (`Trail.roughDistanceKm`) — a flat per-stop
  heuristic for the demo. Replace with a real routing API (e.g. OSRM) once
  you're computing actual walking distance between ordered stops.

## Not included (by design, scoped to the Build tab)

- No transaction/rollback: if a stop's document creation fails partway
  through, earlier stops and the trail document aren't cleaned up. Fine for
  a hackathon demo; for production, consider an Appwrite Function that does
  this server-side atomically instead of writing from the client in a loop.
- No auth — `authorId` is passed in from wherever your app already tracks
  the signed-in user.

