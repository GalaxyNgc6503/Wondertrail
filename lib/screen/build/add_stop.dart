import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trail_stop.dart';
import '../../services/geocoding_service.dart';
import '../../theme/app_theme.dart';
import 'trail_draft.dart';

const int _maxPhotosPerStop = 6;

/// "Stop Details" — its own full screen (not a modal sheet), used for both
/// adding a new stop and editing an existing one (pre-filled).
class AddStopScreen extends StatefulWidget {
  const AddStopScreen({super.key, this.initial});

  /// Pass an existing draft to edit it; omit to create a new stop.
  final StopDraft? initial;

  @override
  State<AddStopScreen> createState() => _AddStopScreenState();
}

class _AddStopScreenState extends State<AddStopScreen> {
  late final StopDraft _draft =
      widget.initial != null ? widget.initial!.copy() : StopDraft();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _locationSearchController =
      TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  final TextEditingController _tipsController = TextEditingController();

  final GeocodingService _geocoding = GeocodingService();
  final MapController _mapController = MapController();

  List<GeocodingResult> _suggestions = <GeocodingResult>[];
  bool _searching = false;

  bool get _locationChosen => _draft.hasLocation;

  @override
  void initState() {
    super.initState();
    _nameController.text = _draft.name;
    _noteController.text = _draft.note;
    _timeController.text = _draft.recommendedTimeMinutes?.toString() ?? '';
    _costController.text = _draft.estimatedCost ?? '';
    _tipsController.text = _draft.tips ?? '';
    if (_draft.hasLocation) {
      _locationSearchController.text = _draft.locationLabel;
    }
    _nameController.addListener(() => _draft.name = _nameController.text);
    _noteController.addListener(() => _draft.note = _noteController.text);
    _timeController.addListener(() {
      _draft.recommendedTimeMinutes = int.tryParse(_timeController.text);
    });
    _costController.addListener(() => _draft.estimatedCost = _costController.text);
    _tipsController.addListener(() => _draft.tips = _tipsController.text);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _locationSearchController.dispose();
    _timeController.dispose();
    _costController.dispose();
    _tipsController.dispose();
    _geocoding.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() => _searching = query.trim().isNotEmpty);
    _geocoding.searchDebounced(
      query: query,
      onResults: (List<GeocodingResult> results) {
        if (!mounted) return;
        setState(() {
          _suggestions = results;
          _searching = false;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _searching = false);
      },
    );
  }

  void _chooseLocation(String label, LatLng point) {
    setState(() {
      _draft.locationLabel = label;
      _draft.lat = point.latitude;
      _draft.lng = point.longitude;
      _suggestions = const <GeocodingResult>[];
    });
    FocusScope.of(context).unfocus();
  }

  void _changeLocation() {
    setState(() {
      _draft.lat = null;
      _draft.lng = null;
    });
  }

  Future<void> _addPhotos() async {
    final int remaining = _maxPhotosPerStop - _draft.photos.length;
    if (remaining <= 0) return;
    final List<XFile> picked =
        await ImagePicker().pickMultiImage(limit: remaining);
    if (picked.isEmpty) return;
    setState(() {
      _draft.photos = <XFile>[
        ..._draft.photos,
        ...picked.take(remaining),
      ];
    });
  }

  void _removePhoto(int index) {
    setState(() => _draft.photos.removeAt(index));
  }

  void _save() {
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.initial != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit stop' : 'Add a stop')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: <Widget>[
            Text('Location', style: AppText.sectionHeading()),
            const SizedBox(height: 10),
            if (_locationChosen)
              _LocationChip(
                label: _draft.locationLabel,
                onChange: _changeLocation,
              )
            else
              _LocationPicker(
                searchController: _locationSearchController,
                onSearchChanged: _onSearchChanged,
                searching: _searching,
                suggestions: _suggestions,
                mapController: _mapController,
                onSuggestionSelected: (GeocodingResult r) =>
                    _chooseLocation(r.label, r.point),
                onMapTap: (LatLng point) =>
                    _chooseLocation('Dropped pin', point),
              ),
            const SizedBox(height: 24),
            Text('Photos', style: AppText.sectionHeading()),
            const SizedBox(height: 4),
            Text('Up to $_maxPhotosPerStop', style: AppText.caption()),
            const SizedBox(height: 10),
            _PhotoStrip(
              photos: _draft.photos,
              onAdd: _addPhotos,
              onRemove: _removePhoto,
            ),
            const SizedBox(height: 24),
            _LabeledField(
              label: 'Name',
              child: TextField(
                controller: _nameController,
                style: AppText.body(),
                decoration: const InputDecoration(hintText: 'Stop name'),
              ),
            ),
            const SizedBox(height: 16),
            _LabeledField(
              label: 'Why visit? (one line)',
              child: TextField(
                controller: _noteController,
                style: AppText.body(),
                decoration: const InputDecoration(
                  hintText: 'What makes this worth a stop',
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Category', style: AppText.sectionHeading()),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: kCategories.map((String c) {
                final bool selected = c == _draft.category;
                return ChoiceChip(
                  label: Text(c),
                  selected: selected,
                  labelStyle: AppText.label(
                    color: selected ? AppColors.parchment50 : AppColors.ink,
                  ),
                  onSelected: (_) => setState(() => _draft.category = c),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: _LabeledField(
                    label: 'Recommended time (min)',
                    child: TextField(
                      controller: _timeController,
                      keyboardType: TextInputType.number,
                      style: AppText.stat(),
                      decoration: const InputDecoration(hintText: 'e.g. 45'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _LabeledField(
                    label: 'Estimated cost',
                    child: TextField(
                      controller: _costController,
                      style: AppText.body(),
                      decoration:
                          const InputDecoration(hintText: 'e.g. RM10–20'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _LabeledField(
              label: 'Traveller tips (optional)',
              child: TextField(
                controller: _tipsController,
                style: AppText.body(),
                maxLines: 3,
                decoration:
                    const InputDecoration(hintText: 'Anything worth knowing'),
              ),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _draft.crossTrailAvailable,
              onChanged: (bool v) => setState(() => _draft.crossTrailAvailable = v),
              activeColor: AppColors.blaze600,
              title: Text('🎲 Available for cross-trail rolls',
                  style: AppText.bodyStrong()),
            ),
            const SizedBox(height: 12),
            // ValueListenableBuilder keeps the button's enabled state live
            // as the person types — reading `_nameController.text` once at
            // build time would go stale (a TextEditingController is a
            // ValueListenable<TextEditingValue>, so listen to it directly).
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _nameController,
              builder: (BuildContext context, TextEditingValue value, _) {
                final bool canSave =
                    value.text.trim().isNotEmpty && _locationChosen;
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canSave ? _save : null,
                    child: const Text('Save stop'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppText.label()),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.label, required this.onChange});
  final String label;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.parchment100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: <Widget>[
          const Text('📍 '),
          Expanded(
            child: Text(label, style: AppText.body(), overflow: TextOverflow.ellipsis),
          ),
          TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}

class _LocationPicker extends StatelessWidget {
  const _LocationPicker({
    required this.searchController,
    required this.onSearchChanged,
    required this.searching,
    required this.suggestions,
    required this.mapController,
    required this.onSuggestionSelected,
    required this.onMapTap,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool searching;
  final List<GeocodingResult> suggestions;
  final MapController mapController;
  final ValueChanged<GeocodingResult> onSuggestionSelected;
  final ValueChanged<LatLng> onMapTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          style: AppText.body(),
          decoration: InputDecoration(
            hintText: 'Search for this stop, or tap the map',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.parchment100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int i) {
                final GeocodingResult r = suggestions[i];
                return ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.place_outlined, color: AppColors.blaze600),
                  title: Text(r.label, style: AppText.body()),
                  onTap: () => onSuggestionSelected(r),
                );
              },
            ),
          ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 200,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: const LatLng(20, 0),
                initialZoom: 2,
                onTap: (_, LatLng point) => onMapTap(point),
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'app.wondertrail.mobile',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('Tap the map to drop a pin', style: AppText.caption()),
      ],
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<XFile> photos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final bool canAddMore = photos.length < _maxPhotosPerStop;

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length + (canAddMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int i) {
          if (i == photos.length) {
            return _AddPhotoTile(onTap: onAdd);
          }
          return _PhotoThumb(
            file: photos[i],
            isCover: i == 0,
            onRemove: () => onRemove(i),
          );
        },
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.file,
    required this.isCover,
    required this.onRemove,
  });

  final XFile file;
  final bool isCover;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 96,
              height: 96,
              child: FutureBuilder<Uint8List>(
                future: file.readAsBytes(),
                builder: (BuildContext context, AsyncSnapshot<Uint8List> snap) {
                  if (!snap.hasData) {
                    return Container(color: AppColors.parchment100);
                  }
                  return Image.memory(snap.data!, fit: BoxFit.cover);
                },
              ),
            ),
          ),
          if (isCover)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.pine950.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Cover',
                    style: AppText.caption(color: AppColors.parchment50)
                        .copyWith(fontSize: 10)),
              ),
            ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.pine950.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.parchment100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ink.withValues(alpha: 0.15)),
        ),
        child: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.ink),
      ),
    );
  }
}
