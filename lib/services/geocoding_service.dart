import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A single result from Komoot's Photon geocoding API.
class PlaceResult {
  const PlaceResult({required this.name, required this.subtitle, required this.latLng});

  final String name;

  /// City/state/country, for the secondary line under the name — the same
  /// "primary + secondary text" shape Google's Places Autocomplete uses.
  final String subtitle;
  final LatLng latLng;

  factory PlaceResult.fromPhotonFeature(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>;
    final coords = (feature['geometry']['coordinates'] as List<dynamic>).cast<num>();
    final subtitleParts = [props['city'], props['state'], props['country']]
        .whereType<String>()
        .toList();

    return PlaceResult(
      name: (props['name'] ?? props['street'] ?? 'Unnamed place') as String,
      subtitle: subtitleParts.join(', '),
      latLng: LatLng(coords[1].toDouble(), coords[0].toDouble()),
    );
  }
}

/// Thrown when Photon doesn't respond within [GeocodingService._timeout] —
/// kept distinct from other failures so callers can show a more specific
/// "this is just a slow demo server" message instead of a generic one.
class GeocodingTimeoutException implements Exception {
  @override
  String toString() => 'Geocoding search timed out';
}

/// Live location search, backed by Komoot's Photon API.
///
/// Deliberately **not** Nominatim — Nominatim's usage policy lists
/// "Auto-complete search" under *Unacceptable Use* outright, not just a
/// rate limit. Photon is the OSM ecosystem's own answer built specifically
/// for search-as-you-type.
///
/// Sends a real `User-Agent` on every request — Photon's server blocks
/// Dart's default UA string (`Dart/3.x (dart:io)`) as an anti-scraping
/// measure, which shows up as a plain 403 with no other explanation.
///
/// `photon.komoot.io` is a free public demo instance with **no uptime or
/// latency guarantee** — komoot says so themselves. Requests here time out
/// after [_timeout] rather than hanging indefinitely if it's slow, but a
/// timeout doesn't fix slowness, it just stops it from looking like the app
/// froze. If consistent low latency matters, self-host Photon/Nominatim or
/// use a paid provider (Mapbox, LocationIQ, Google Places) instead.
///
/// This class only does the fetch-and-parse; each screen that uses it still
/// owns its own debounce `Timer` and stale-response request-ID (those are
/// UI-lifecycle concerns, not search concerns) — see `add_stop.dart` for
/// the reference pattern.
class GeocodingService {
  static const _timeout = Duration(seconds: 8);

  /// Returns up to [limit] matches for [query]. [bias] nudges ranking
  /// toward a location — the same idea as Google biasing by viewport —
  /// pass the current map center or the user's location when you have one.
  /// When [bias] is set, this also sends a `bbox` scoped to roughly
  /// [bboxDegrees] around it, which restricts what Photon actually searches
  /// (not just how it ranks) — the real lever for latency on the public
  /// demo instance, which otherwise scans its entire planet index per
  /// query. Widen [bboxDegrees] if a search legitimately needs to find
  /// something farther from [bias] than that covers.
  ///
  /// Throws [GeocodingTimeoutException] if Photon doesn't respond within
  /// [_timeout], or a plain [Exception] for any other failure (non-200
  /// status, network error, bad JSON).
  Future<List<PlaceResult>> search(
    String query, {
    LatLng? bias,
    int limit = 5,
    double bboxDegrees = 0.5,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': trimmed,
      'limit': '$limit',
      if (bias != null) 'lat': '${bias.latitude}',
      if (bias != null) 'lon': '${bias.longitude}',
      if (bias != null)
        'bbox':
            '${bias.longitude - bboxDegrees},${bias.latitude - bboxDegrees},'
            '${bias.longitude + bboxDegrees},${bias.latitude + bboxDegrees}',
    });

    // Photon blocks requests carrying Dart's default User-Agent
    // ("Dart/3.x (dart:io)") as anti-scraping protection — this is what
    // was causing 403s. A real, identifying User-Agent avoids that.
    final http.Response response;
    try {
      response = await http
          .get(
            uri,
            headers: const {'User-Agent': 'Wondertrail/1.0 (Flutter; +https://github.com/wondertrail)'},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw GeocodingTimeoutException();
    }

    if (response.statusCode != 200) {
      throw Exception('Photon returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (data['features'] as List<dynamic>).cast<Map<String, dynamic>>();
    return features.map(PlaceResult.fromPhotonFeature).toList();
  }
}
