import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models/trail_stop.dart';
import '../theme/app_theme.dart';

/// Shown right after a location is picked. Collects a photo, a name, and a
/// one-line note, then returns a fully-formed [TrailStop].
///
/// ```dart
/// final stop = await showModalBottomSheet<TrailStop>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => StopDetailSheet(locationLabel: picked.label, latLng: picked.latLng),
/// );
/// ```
class StopDetailSheet extends StatefulWidget {
  const StopDetailSheet({super.key, required this.locationLabel, required this.latLng});

  final String locationLabel;
  final LatLng latLng;

  @override
  State<StopDetailSheet> createState() => _StopDetailSheetState();
}

class _StopDetailSheetState extends State<StopDetailSheet> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  File? _photo;

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  void _submit() {
    final name = _nameController.text.trim().isEmpty ? widget.locationLabel : _nameController.text.trim();
    final note = _noteController.text.trim().isEmpty ? widget.locationLabel : _noteController.text.trim();
    Navigator.of(context).pop(
      TrailStop(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        note: note,
        location: widget.latLng,
        photo: _photo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.parchment100,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.ink.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 14, color: AppColors.moss600),
                const SizedBox(width: 6),
                Text(widget.locationLabel, style: AppText.mono(color: AppColors.moss600)),
              ],
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                height: 130,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: _photo == null
                      ? Border.all(color: AppColors.ink.withOpacity(0.25), width: 1.5, style: BorderStyle.solid)
                      : null,
                  image: _photo != null
                      ? DecorationImage(image: FileImage(_photo!), fit: BoxFit.cover)
                      : null,
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
            ),
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink.withOpacity(0.55),
                      side: BorderSide(color: AppColors.ink.withOpacity(0.18)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blaze600,
                      foregroundColor: AppColors.parchment50,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _submit,
                    child: const Text('Add to trail'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body(size: 13, color: AppColors.ink.withOpacity(0.4)),
      filled: true,
      fillColor: AppColors.parchment50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.ink.withOpacity(0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.blaze600),
      ),
    );
  }
}
