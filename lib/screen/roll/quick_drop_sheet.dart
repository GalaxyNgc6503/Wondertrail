import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trail_stop.dart';
import '../../services/trail_repository.dart';
import '../../theme/app_theme.dart';

/// Long-pressing an empty spot on the Roll map opens this. It's
/// deliberately smaller than the full Build wizard — a name, a category,
/// an optional note and a single optional photo — because the point is a
/// fast "I found something, save it" action, not a second wizard. What it
/// writes is a real single-stop trail via [TrailRepository.quickDropStop],
/// public and cross-trail-discoverable like everything else, so it's
/// rollable by anyone (including the person who just dropped it) the
/// moment it saves.
///
/// Shown with `showModalBottomSheet<Trail>`; returns the newly created
/// (single-stop) trail on success, or null if the sheet was dismissed.
/// It returns the whole trail rather than just the stop because the Roll
/// map treats a dropped pin like any other trail and moves onto it.
class QuickDropSheet extends StatefulWidget {
  const QuickDropSheet({super.key, required this.point});

  final LatLng point;

  @override
  State<QuickDropSheet> createState() => _QuickDropSheetState();
}

class _QuickDropSheetState extends State<QuickDropSheet> {
  final TrailRepository _repository = TrailRepository();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  String _category = kCategories.first;
  XFile? _photo;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final XFile? file =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _photo = file);
  }

  String get _locationLabel {
    // No reverse-geocoding wired up (Photon supports it, but this build
    // only ever does forward search) — plain coordinates are an honest
    // fallback rather than guessing a place name.
    return '${widget.point.latitude.toStringAsFixed(5)}, '
        '${widget.point.longitude.toStringAsFixed(5)}';
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final Trail trail = await _repository.quickDropStop(
        name: name,
        note: _noteController.text.trim(),
        category: _category,
        lat: widget.point.latitude,
        lng: widget.point.longitude,
        locationLabel: _locationLabel,
        photo: _photo,
        authorId: kDemoAuthorId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(trail);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't save this spot — check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Drop a pin here', style: AppText.sectionHeading()),
            const SizedBox(height: 4),
            Text(_locationLabel, style: AppText.caption()),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: AppText.body(),
              decoration: const InputDecoration(hintText: 'What is this spot?'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: kCategories.map((String c) {
                final bool selected = c == _category;
                return ChoiceChip(
                  label: Text(c),
                  selected: selected,
                  labelStyle: AppText.label(
                    color: selected ? AppColors.parchment50 : AppColors.ink,
                  ),
                  onSelected: (_) => setState(() => _category = c),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              style: AppText.body(),
              decoration: const InputDecoration(
                hintText: 'Why is it worth a visit? (optional)',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                if (_photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: FutureBuilder<Uint8List>(
                        future: _photo!.readAsBytes(),
                        builder: (BuildContext context, AsyncSnapshot<Uint8List> snap) {
                          if (!snap.hasData) {
                            return Container(color: AppColors.parchment100);
                          }
                          return Image.memory(snap.data!, fit: BoxFit.cover);
                        },
                      ),
                    ),
                  )
                else
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _pickPhoto,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.parchment100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.ink.withValues(alpha: 0.15)),
                      ),
                      child: const Icon(Icons.add_a_photo_outlined, color: AppColors.ink),
                    ),
                  ),
                const SizedBox(width: 10),
                Text('Photo (optional)', style: AppText.caption()),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!, style: AppText.caption(color: AppColors.blaze700)),
            ],
            const SizedBox(height: 20),
            // ValueListenableBuilder so the button's enabled state stays
            // live as the person types, rather than reading the
            // controller's text once at build time.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _nameController,
              builder: (BuildContext context, TextEditingValue value, _) {
                final bool canSave = value.text.trim().isNotEmpty && !_saving;
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canSave ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold500,
                      foregroundColor: AppColors.pine950,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.pine950,
                            ),
                          )
                        : const Text('Save to the map'),
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
