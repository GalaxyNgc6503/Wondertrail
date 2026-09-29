import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

/// Result returned when the sheet is dismissed with a chosen location.
class PickedLocation {
  PickedLocation({required this.label, required this.latLng});
  final String label;
  final LatLng latLng;
}

/// A mock nearby-place suggestion. In production, replace [MockPlace.all]
/// with a real geocoding/places lookup (reverse geocoding, free-tier API —
/// see the app's "Location accuracy" risk mitigation).
class MockPlace {
  const MockPlace(this.name, this.distanceLabel, this.latLng);
  final String name;
  final String distanceLabel;
  final LatLng latLng;

  static const all = [
    MockPlace('Riverside Steps', '0.4 km away', LatLng(39.9526, -75.1632)),
    MockPlace('Cedar Street Café', '0.7 km away', LatLng(39.9510, -75.1610)),
  ];
}

/// Search bar that expands into either a suggestion list or a tappable map.
/// Push with `Navigator.push` / `showModalBottomSheet` and await the result:
///
/// ```dart
/// final picked = await showModalBottomSheet<PickedLocation>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => const LocationPickerSheet(),
/// );
/// ```
class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({
    super.key,
    this.initialCenter = const LatLng(39.9526, -75.1652), // demo center
  });

  final LatLng initialCenter;

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  bool _mapOpen = false;
  LatLng? _droppedPin;
  final _searchController = TextEditingController();

  void _confirm(PickedLocation location) {
    Navigator.of(context).pop(location);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _mapOpen ? 0.75 : 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.parchment50,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.ink.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              _buildSearchBar(),
              if (!_mapOpen) ..._buildSuggestionList(),
              if (_mapOpen) Expanded(child: _buildMap()),
              if (_mapOpen && _droppedPin != null) _buildPinConfirm(),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        style: AppText.body(size: 13.5),
        decoration: InputDecoration(
          hintText: 'Search for a location…',
          hintStyle: AppText.body(size: 13.5, color: AppColors.ink.withOpacity(0.4)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.black45),
          filled: true,
          fillColor: AppColors.parchment100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  List<Widget> _buildSuggestionList() {
    return [
      ...MockPlace.all.map(
        (place) => ListTile(
          leading: const Icon(Icons.circle, size: 12, color: AppColors.blaze700),
          title: Text(place.name, style: AppText.body(size: 13, weight: FontWeight.w600)),
          subtitle: Text(place.distanceLabel, style: AppText.body(size: 11, color: Colors.black45)),
          onTap: () => _confirm(PickedLocation(label: place.name, latLng: place.latLng)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.add_location_alt_outlined, size: 18, color: AppColors.blaze700),
        title: Text('Drop a pin manually', style: AppText.body(size: 13, weight: FontWeight.w600)),
        subtitle: Text('Pick the exact spot on the map', style: AppText.body(size: 11, color: Colors.black45)),
        onTap: () => setState(() => _mapOpen = true),
      ),
    ];
  }

  Widget _buildMap() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: widget.initialCenter,
                initialZoom: 15,
                onTap: (tapPosition, point) => setState(() => _droppedPin = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.wondertrail.app',
                ),
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                ),
                if (_droppedPin != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _droppedPin!,
                      width: 34,
                      height: 34,
                      child: const Icon(Icons.location_on, color: AppColors.blaze600, size: 34),
                    ),
                  ]),
              ],
            ),
            if (_droppedPin == null)
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Text(
                  'Tap anywhere on the map to drop a pin',
                  textAlign: TextAlign.center,
                  style: AppText.mono(size: 10.5, color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinConfirm() {
    final lat = _droppedPin!.latitude.toStringAsFixed(4);
    final lng = _droppedPin!.longitude.toStringAsFixed(4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$lat° N, $lng° W', style: AppText.mono()),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blaze600,
              foregroundColor: AppColors.parchment50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _confirm(PickedLocation(label: 'Dropped pin', latLng: _droppedPin!)),
            child: const Text('Use this location'),
          ),
        ],
      ),
    );
  }
}
