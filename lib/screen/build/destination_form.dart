import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../models/destination.dart';
import '../../models/trail_stop.dart' show kCategories;
import '../../theme/app_theme.dart';
import '../../widgets/destination_view.dart';

/// Add/edit a destination at a fixed [location]: photo, name, description,
/// category, visit time, cost, tips — then a preview before it publishes.
///
/// Pushed as a full page (`Navigator.push<Destination>`) so the map
/// underneath stays untouched until the user commits or backs out.
class DestinationFormPage extends StatefulWidget {
  const DestinationFormPage({
    super.key,
    required this.location,
    required this.userId,
    this.initial,
  });

  final LatLng location;
  final String userId;

  /// Editing an existing destination the user owns.
  final Destination? initial;

  @override
  State<DestinationFormPage> createState() => _DestinationFormPageState();
}

class _DestinationFormPageState extends State<DestinationFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _timeController = TextEditingController(text: '30');
  final _costController = TextEditingController(text: 'Free');
  final _tipsController = TextEditingController();
  String _category = kCategories.first;
  File? _photo;
  String? _existingPhotoFileId;
  bool _showingPreview = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _nameController.text = initial.name;
      _descriptionController.text = initial.description;
      _timeController.text = initial.visitMinutes.toString();
      _costController.text = initial.cost;
      _tipsController.text = initial.tips ?? '';
      _category = initial.category;
      _existingPhotoFileId = initial.photoFileId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _timeController.dispose();
    _costController.dispose();
    _tipsController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  void _removePhoto() => setState(() {
        _photo = null;
        _existingPhotoFileId = null;
      });

  Destination _buildDraft() {
    return Destination(
      id: widget.initial?.id ?? '',
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _category,
      visitMinutes: int.tryParse(_timeController.text.trim()) ?? 30,
      cost: _costController.text.trim().isEmpty ? 'Free' : _costController.text.trim(),
      tips: _tipsController.text.trim().isEmpty ? null : _tipsController.text.trim(),
      location: widget.location,
      localPhoto: _photo,
      photoFileId: _existingPhotoFileId,
      authorId: widget.userId,
      source: DestinationSource.community,
    );
  }

  void _goToPreview() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _showingPreview = true);
  }

  void _publish() => Navigator.pop(context, _buildDraft());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment50,
      appBar: AppBar(
        backgroundColor: AppColors.parchment50,
        elevation: 0,
        leading: BackButton(
          onPressed: () {
            if (_showingPreview) {
              setState(() => _showingPreview = false);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _showingPreview ? 'Preview' : (_isEditing ? 'Edit destination' : 'New destination'),
          style: AppText.headline(size: 18),
        ),
      ),
      body: _showingPreview ? _buildPreview() : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Stack(children: [
      Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
          children: [
          _photoPicker(),
          const SizedBox(height: 20),
          _label('Name'),
          TextFormField(
            controller: _nameController,
            style: AppText.body(size: 14.5),
            decoration: _inputDecoration('e.g. Hidden courtyard café'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Give this place a name' : null,
          ),
          const SizedBox(height: 16),
          _label('Description'),
          TextFormField(
            controller: _descriptionController,
            style: AppText.body(size: 14.5),
            maxLines: 3,
            decoration: _inputDecoration('What makes it worth a stop?'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Add a short description' : null,
          ),
          const SizedBox(height: 16),
          _label('Category'),
          _categoryPicker(),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Visit time (min)'),
                TextFormField(
                  controller: _timeController,
                  style: AppText.body(size: 14.5),
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('30'),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    return (n == null || n <= 0) ? 'Enter minutes' : null;
                  },
                ),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Cost'),
                TextFormField(
                  controller: _costController,
                  style: AppText.body(size: 14.5),
                  decoration: _inputDecoration('Free, \$5, RM10–20…'),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          _label('Travel tips', optional: true),
          TextFormField(
            controller: _tipsController,
            style: AppText.body(size: 14.5),
            maxLines: 2,
            decoration: _inputDecoration('Go at sunset, cash only…'),
          ),
        ],
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: _bottomBar(rightLabel: 'Preview', onRight: _goToPreview),
      ),
    ]);
  }

  Widget _photoPicker() {
    final hasPhoto = _photo != null || _existingPhotoFileId != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Photo', optional: true),
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: hasPhoto
            ? Stack(children: [
                DestinationPhoto(destination: _buildDraft(), width: double.infinity, height: 170),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _photoAction(icon: Icons.close, onTap: _removePhoto),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: _photoAction(icon: Icons.edit, onTap: () => _pickPhoto(ImageSource.gallery)),
                ),
              ])
            : InkWell(
                onTap: () => _pickPhoto(ImageSource.gallery),
                onLongPress: () => _pickPhoto(ImageSource.camera),
                child: Container(
                  width: double.infinity,
                  height: 130,
                  decoration: BoxDecoration(
                    color: AppColors.parchment100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.ink.withValues(alpha: 0.12), style: BorderStyle.solid),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.add_a_photo_outlined, color: AppColors.moss600),
                    const SizedBox(height: 6),
                    Text('Add a photo', style: AppText.body(size: 12.5, color: Colors.black54)),
                  ]),
                ),
              ),
      ),
    ]);
  }

  Widget _photoAction({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 16, color: Colors.white)),
      ),
    );
  }

  Widget _categoryPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kCategories.map((cat) {
        final selected = cat == _category;
        return ChoiceChip(
          label: Text(cat, style: AppText.body(size: 12.5, weight: FontWeight.w600, color: selected ? AppColors.parchment50 : AppColors.ink)),
          selected: selected,
          showCheckmark: false,
          selectedColor: AppColors.pine800,
          backgroundColor: AppColors.parchment100,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide.none),
          onSelected: (_) => setState(() => _category = cat),
        );
      }).toList(),
    );
  }

  Widget _label(String text, {bool optional = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Text(text, style: AppText.body(size: 12.5, weight: FontWeight.w600, color: Colors.black54)),
        if (optional) ...[
          const SizedBox(width: 6),
          Text('optional', style: AppText.body(size: 11, color: Colors.black38)),
        ],
      ]),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(size: 13.5, color: AppColors.ink.withValues(alpha: 0.35)),
        filled: true,
        fillColor: AppColors.parchment100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.blaze600)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _buildPreview() {
    return Stack(children: [
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            "This is how travellers will see it on the map.",
            style: AppText.body(size: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          DestinationDetail(destination: _buildDraft(), userId: widget.userId),
        ]),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: _bottomBar(
          leftLabel: '← Edit',
          onLeft: () => setState(() => _showingPreview = false),
          rightLabel: _isEditing ? 'Save changes' : 'Publish destination',
          onRight: _publish,
        ),
      ),
    ]);
  }

  Widget _bottomBar({
    String? leftLabel,
    VoidCallback? onLeft,
    required String rightLabel,
    required VoidCallback onRight,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.parchment50,
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, -3))],
      ),
      child: Row(children: [
        if (leftLabel != null)
          TextButton(
            onPressed: onLeft,
            child: Text(leftLabel, style: AppText.body(size: 13.5, weight: FontWeight.w600, color: AppColors.ink)),
          ),
        const Spacer(),
        ElevatedButton(
          onPressed: onRight,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blaze600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(rightLabel, style: AppText.body(size: 13.5, weight: FontWeight.w700, color: Colors.white)),
        ),
      ]),
    );
  }
}
