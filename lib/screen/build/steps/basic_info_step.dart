import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/geocoding_service.dart';
import '../../../theme/app_theme.dart';
import '../trail_draft.dart';

class BasicInfoStep extends StatefulWidget {
  const BasicInfoStep({
    super.key,
    required this.draft,
    required this.onDraftChanged,
  });

  final TrailDraft draft;
  final VoidCallback onDraftChanged;

  @override
  State<BasicInfoStep> createState() => _BasicInfoStepState();
}

class _BasicInfoStepState extends State<BasicInfoStep> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final GeocodingService _geocoding = GeocodingService();

  List<GeocodingResult> _suggestions = <GeocodingResult>[];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.draft.title;
    _descriptionController.text = widget.draft.description;
    if (widget.draft.startingLocation != null) {
      _locationController.text = widget.draft.startingLocation!.label;
    }
    _titleController.addListener(() {
      widget.draft.title = _titleController.text;
      widget.onDraftChanged();
    });
    _descriptionController.addListener(() {
      widget.draft.description = _descriptionController.text;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _geocoding.dispose();
    super.dispose();
  }

  void _onLocationQueryChanged(String query) {
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

  void _selectLocation(GeocodingResult result) {
    setState(() {
      widget.draft.startingLocation = result;
      _locationController.text = result.label;
      _suggestions = const <GeocodingResult>[];
    });
    FocusScope.of(context).unfocus();
    widget.onDraftChanged();
  }

  Future<void> _pickCover() async {
    final XFile? file =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => widget.draft.coverPhoto = file);
    widget.onDraftChanged();
  }

  void _clearCover() {
    setState(() => widget.draft.coverPhoto = null);
    widget.onDraftChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: <Widget>[
        Text('Trail name', style: AppText.sectionHeading()),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          style: AppText.body(),
          decoration: const InputDecoration(hintText: 'e.g. Riverside Ramble'),
        ),
        const SizedBox(height: 24),
        Text('Starting location', style: AppText.sectionHeading()),
        const SizedBox(height: 8),
        TextField(
          controller: _locationController,
          onChanged: _onLocationQueryChanged,
          style: AppText.body(),
          decoration: InputDecoration(
            hintText: 'Search for where this trail begins',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
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
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppColors.parchment100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int i) {
                final GeocodingResult r = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.place_outlined, color: AppColors.blaze600),
                  title: Text(r.label, style: AppText.body()),
                  onTap: () => _selectLocation(r),
                );
              },
            ),
          ),
        const SizedBox(height: 24),
        Text('Cover photo', style: AppText.sectionHeading()),
        const SizedBox(height: 4),
        Text(
          "Optional — falls back to your first stop's first photo if skipped.",
          style: AppText.caption(),
        ),
        const SizedBox(height: 10),
        _CoverPicker(
          file: widget.draft.coverPhoto,
          onPick: _pickCover,
          onClear: _clearCover,
        ),
        const SizedBox(height: 24),
        Text('Description', style: AppText.sectionHeading()),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          style: AppText.body(),
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'What is this trail about?',
          ),
        ),
      ],
    );
  }
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({required this.file, required this.onPick, required this.onClear});

  final XFile? file;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPick,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.parchment100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.15)),
          ),
          child: const Center(
            child: Icon(Icons.add_photo_alternate_outlined, color: AppColors.ink),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: <Widget>[
          SizedBox(
            height: 140,
            width: double.infinity,
            child: FutureBuilder<Uint8List>(
              future: file!.readAsBytes(),
              builder: (BuildContext context, AsyncSnapshot<Uint8List> snap) {
                if (!snap.hasData) {
                  return Container(color: AppColors.parchment100);
                }
                return Image.memory(snap.data!, fit: BoxFit.cover);
              },
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: GestureDetector(
              onTap: onClear,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.pine950.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
