import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/destination.dart';
import '../models/trail_stop.dart' show kCategories;

/// Thrown when Overpass doesn't respond within [OsmPlacesService._timeout].
class OsmPlacesTimeoutException implements Exception {
  @override
  String toString() => 'OpenStreetMap place lookup timed out';
}

/// Turns raw OSM tags into a rough estimate — real numbers, once someone
/// visits, are what Build's "Edit" is for.
const _defaultVisitMinutes = {'Food': 45, 'View': 20, 'Nature': 40, 'Culture': 60};

/// The other half of "existing destinations": live points of interest
/// pulled from OpenStreetMap (via the Overpass API), merged on the map
/// alongside whatever the community has added in Appwrite. This is what
/// makes a brand-new area on Build already show *something* to fill gaps
/// around, instead of a blank map until someone seeds it by hand.
///
/// Returned destinations use [DestinationSource.curated] with no
/// `authorId`, exactly like a hand-seeded Appwrite document would — so
/// they're automatically read-only (`Destination.isMine` only ever returns
/// true for `community` destinations) with no special-casing needed
/// anywhere else in the app.
class OsmPlacesService {
  static const _timeout = Duration(seconds: 12);

  /// Caps how many nodes Overpass returns per query — keeps both the
  /// request and the marker count reasonable on a dense downtown block.
  static const _maxResults = 80;

  /// OSM tag values, grouped by which of [kCategories] they map to.
  /// Extend these lists to broaden what shows up; the query and the
  /// mapper share this single source of truth so they can't drift apart.
  static const _tagsByCategory = {
    'Food': {'amenity': ['cafe', 'restaurant', 'fast_food', 'bar', 'pub', 'ice_cream']},
    'View': {
      'tourism': ['viewpoint', 'attraction'],
      'natural': ['peak', 'waterfall', 'beach'],
    },
    'Nature': {
      'leisure': ['park', 'garden', 'nature_reserve'],
    },
    'Culture': {
      'tourism': ['museum', 'gallery', 'artwork'],
    },
  };

  /// Every named OSM point of interest inside the given box. Points with no
  /// `name` tag are skipped — an unnamed node makes a useless destination
  /// pin. Returns an empty list (never throws) on a request that fails for
  /// a reason other than a timeout, since this is supplementary data: a
  /// blip in Overpass shouldn't block the rest of the map from loading.
  Future<List<Destination>> listInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    final query = _buildQuery(south: south, west: west, north: north, east: east);

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            headers: const {'User-Agent': 'Wondertrail/1.0 (Flutter; +https://github.com/wondertrail)'},
            body: {'data': query},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw OsmPlacesTimeoutException();
    } catch (e) {
      debugPrint('OsmPlacesService: request failed — $e');
      return const [];
    }

    if (response.statusCode != 200) {
      debugPrint('OsmPlacesService: Overpass returned ${response.statusCode} — ${response.body}');
      return const [];
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List<dynamic>).cast<Map<String, dynamic>>();
      final results = elements.map(_toDestination).whereType<Destination>().toList();
      debugPrint('OsmPlacesService: ${elements.length} elements → ${results.length} named destinations');
      return results;
    } catch (e) {
      debugPrint('OsmPlacesService: failed to parse response — $e');
      return const [];
    }
  }

  String _buildQuery({required double south, required double west, required double north, required double east}) {
    final bbox = '$south,$west,$north,$east';
    final clauses = StringBuffer();
    for (final categoryTags in _tagsByCategory.values) {
      for (final entry in categoryTags.entries) {
        final values = entry.value.join('|');
        clauses.writeln('node["${entry.key}"~"^($values)\$"]($bbox);');
      }
    }
    return '[out:json][timeout:${_timeout.inSeconds}];($clauses);out center $_maxResults;';
  }

  Destination? _toDestination(Map<String, dynamic> element) {
    final tags = (element['tags'] as Map<String, dynamic>?) ?? const {};
    final name = tags['name'] as String?;
    if (name == null || name.trim().isEmpty) return null;

    final lat = (element['lat'] as num?)?.toDouble();
    final lon = (element['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;

    final category = _categoryFor(tags);
    final fee = tags['fee'] as String?;
    final openingHours = tags['opening_hours'] as String?;

    return Destination(
      id: 'osm:${element['id']}',
      name: name.trim(),
      description: _describe(tags, category),
      category: category,
      visitMinutes: _defaultVisitMinutes[category] ?? 30,
      cost: fee == 'yes' ? 'Paid' : (fee == 'no' ? 'Free' : 'Varies'),
      tips: openingHours == null ? null : 'Hours: $openingHours',
      location: LatLng(lat, lon),
      source: DestinationSource.curated,
    );
  }

  String _categoryFor(Map<String, dynamic> tags) {
    for (final entry in _tagsByCategory.entries) {
      for (final tagEntry in entry.value.entries) {
        if (tagEntry.value.contains(tags[tagEntry.key])) return entry.key;
      }
    }
    return kCategories.first;
  }

  String _describe(Map<String, dynamic> tags, String category) {
    final cuisine = (tags['cuisine'] as String?)?.replaceAll('_', ' ');
    if (cuisine != null && cuisine.isNotEmpty) return '${_cap(cuisine)} spot, via OpenStreetMap.';
    final description = tags['description'] as String?;
    if (description != null && description.trim().isNotEmpty) return description.trim();
    return 'A $category destination from OpenStreetMap — add a description from Build to improve it.';
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
