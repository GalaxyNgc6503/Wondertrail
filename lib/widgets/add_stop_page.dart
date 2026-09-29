import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';

import '../models/trail_stop.dart';
import '../theme/app_theme.dart';

/// A mock place used only to make the search bar's "recenter the map"
/// behavior demoable without a real geocoding API. In production, replace
/// this with a real reverse-geocoding lookup (see the app's "Location
/// accuracy" risk mitigation) that resolves free-text queries to coordinates.
class MockPlace {
  const MockPlace(this.name, this.latLng);
  final String name;
  final LatLng latLng;

  static const all = [
    MockPlace('Riverside Steps', LatLng(39.9526, -75.1632)),
    MockPlace('Cedar Street Café', LatLng(39.9510, -75.1610)),
  ];
}

/// One page for adding a stop: pick a location (search or drop a pin), then
/// add a photo, name, and note — all in a single scroll, no separate sheets.
///
/// ```dart
/// final stop = await Navigator.push<TrailStop>(
///   context,
///   MaterialPageRoute(builder: (_) => const AddStopPage()),
/// );
/// ```
class AddStopPage extends StatefulWidget {
  const AddStopPage({super.key, this.initialMapCenter = const LatLng(39.9526, -75.1652)});

  final LatLng initialMapCenter;

  @override
  State<AddStopPage> createState() => _AddStopPageState();
}

class _AddStopPageState extends State<AddStopPage> {
  // Location
  String? _locationLabel;
  LatLng? _location;
  bool _pickerOpen = true; // starts open since there's nothing chosen yet
  LatLng? _droppedPin;
  final _searchController = TextEditingController();
  final _mapController = MapController();

  // Stop details
  File? _photo;
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  void _chooseLocation(String label, LatLng latLng) {
    setState(() {
      _locationLabel = label;
      _location = latLng;
      _pickerOpen = false;
    });
  }

  void _changeLocation() {
    setState(() {
      _pickerOpen = true;
      _droppedPin = null;
    });
  }

  void _handleSearchSubmit(String query) {
    if (query.trim().isEmpty) return;
    final match = MockPlace.all.where(
      (p) => p.name.toLowerCase().contains(query.trim().toLowerCase()),
    );
    if (match.isNotEmpty) {
      final place = match.first;
      setState(() => _droppedPin = place.latLng);
      _mapController.move(place.latLng, 16);
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  void _submit() {
    if (_location == null) return;
    final label = _locationLabel!;
    final name = _nameController.text.trim().isEmpty ? label : _nameController.text.trim();
    final note = _noteController.text.trim().isEmpty ? label : _noteController.text.trim();
    Navigator.of(context).pop(
      TrailStop(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        note: note,
        location: _location!,
        photo: _photo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment50,
      appBar: AppBar(
        backgroundColor: AppColors.parchment50,
        elevation: 0,
        title: Text('Add a stop', style: AppText.headline()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          _buildLocationSection(),
          const SizedBox(height: 18),
          _buildPhotoTile(),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            style: AppText.body(size: 13),
            decoration: _fieldDecoration('Stop name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteController,
            style: AppText.body(size: 13),
            decoration: _fieldDecoration('One-line note (e.g. "best at golden hour")'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blaze600,
              foregroundColor: AppColors.parchment50,
              disabledBackgroundColor: AppColors.blaze600.withOpacity(0.35),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _location == null ? null : _submit,
            child: Text(
              'Add to trail',
              style: AppText.body(size: 14.5, weight: FontWeight.w600, color: AppColors.parchment50),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Location section: either the picker (search + map) or a compact chip ----
  Widget _buildLocationSection() {
    if (!_pickerOpen && _locationLabel != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.parchment100, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, size: 16, color: AppColors.moss600),
            const SizedBox(width: 8),
            Expanded(child: Text(_locationLabel!, style: AppText.body(size: 13, weight: FontWeight.w600))),
            GestureDetector(
              onTap: _changeLocation,
              child: Text('Change', style: AppText.body(size: 12, weight: FontWeight.w600, color: AppColors.blaze700)),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: AppColors.parchment100, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: _searchController,
              style: AppText.body(size: 13.5),
              textInputAction: TextInputAction.search,
              onSubmitted: _handleSearchSubmit,
              decoration: InputDecoration(
                hintText: 'Search for a location…',
                hintStyle: AppText.body(size: 13.5, color: AppColors.ink.withOpacity(0.4)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.black45),
                filled: true,
                fillColor: AppColors.parchment50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          _buildMap(),
          if (_droppedPin != null) _buildPinConfirm(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 230,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.initialMapCenter,
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
      ),
    );
  }

  Widget _buildPinConfirm() {
    final lat = _droppedPin!.latitude.toStringAsFixed(4);
    final lng = _droppedPin!.longitude.toStringAsFixed(4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
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
            onPressed: () => _chooseLocation('Dropped pin', _droppedPin!),
            child: const Text('Use this location'),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoTile() {
    return GestureDetector(
      onTap: _pickPhoto,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _photo == null ? Border.all(color: AppColors.ink.withOpacity(0.25), width: 1.5) : null,
          image: _photo != null ? DecorationImage(image: FileImage(_photo!), fit: BoxFit.cover) : null,
        ),
        child: _photo == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, size: 20, color: AppColors.ink.withOpacity(0.4)),
                  const SizedBox(height: 6),
                  Text('Add a photo', style: AppText.body(size: 12, weight: FontWeight.w600, color: AppColors.ink.withOpacity(0.45))),
                ],
              )
            : null,
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body(size: 13, color: AppColors.ink.withOpacity(0.4)),
      filled: true,
      fillColor: AppColors.parchment100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.blaze600),
      ),
    );
  }
}
