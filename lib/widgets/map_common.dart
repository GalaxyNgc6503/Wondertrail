import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

const kDefaultMapCenter = LatLng(39.9526, -75.1652);

TileLayer osmTileLayer() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.wondertrail.app',
    );

/// A rough lat/lng box around [center] — good enough for a database query;
/// callers filter by true distance afterwards.
({double south, double west, double north, double east}) boxAround(LatLng center, double radiusKm) {
  final dLat = radiusKm / 111.0;
  final dLng = radiusKm / (111.0 * max(0.2, cos(center.latitude * pi / 180)));
  return (
    south: center.latitude - dLat,
    west: center.longitude - dLng,
    north: center.latitude + dLat,
    east: center.longitude + dLng,
  );
}

/// OSM's tile licence requires visible attribution; the built-in widget sits
/// behind our bottom sheets, so screens place this one at the top instead.
class OsmCredit extends StatelessWidget {
  const OsmCredit({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('© OpenStreetMap contributors', style: AppText.body(size: 9.5, color: Colors.black54)),
    );
  }
}

/// Small round map button (zoom to fit, etc.).
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({super.key, required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.parchment50,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: AppColors.pine800),
      ),
    );
  }
}
