import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/geocoding_service.dart';
import '../theme/app_theme.dart';

/// Search-as-you-type place search (Photon) with a results dropdown.
/// Owns its own debounce + stale-response protection; see [GeocodingService].
class PlaceSearchBar extends StatefulWidget {
  const PlaceSearchBar({
    super.key,
    required this.onSelected,
    this.hint = 'Search a place…',
    this.bias,
    this.bboxDegrees = 1.5,
  });

  final ValueChanged<PlaceResult> onSelected;
  final String hint;

  /// Ranks (and scopes) results near this point when it returns non-null.
  final LatLng? Function()? bias;
  final double bboxDegrees;

  @override
  State<PlaceSearchBar> createState() => _PlaceSearchBarState();
}

class _PlaceSearchBarState extends State<PlaceSearchBar> {
  final _geocoding = GeocodingService();
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  List<PlaceResult> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    final id = ++_requestId;
    setState(() => _searching = true);
    try {
      final results = await _geocoding.search(q, bias: widget.bias?.call(), bboxDegrees: widget.bboxDegrees);
      if (id != _requestId || !mounted) return;
      setState(() => _results = results);
    } catch (e) {
      debugPrint('Search failed: $e');
      if (!mounted || id != _requestId) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.pine950,
        content: Text(
          e is GeocodingTimeoutException
              ? 'Search is taking a while — the free lookup service can be slow.'
              : 'Search failed — check your connection.',
          style: AppText.body(size: 12.5, color: AppColors.parchment50),
        ),
      ));
    } finally {
      if (mounted && id == _requestId) setState(() => _searching = false);
    }
  }

  void _select(PlaceResult place) {
    _controller.text = place.name;
    setState(() => _results = []);
    FocusScope.of(context).unfocus();
    widget.onSelected(place);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(14),
          color: AppColors.parchment50,
          child: TextField(
            controller: _controller,
            style: AppText.body(size: 14),
            onChanged: _onChanged,
            onSubmitted: (q) {
              _debounce?.cancel();
              _search(q);
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppText.body(size: 14, color: AppColors.ink.withValues(alpha: 0.4)),
              prefixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blaze600)),
                    )
                  : const Icon(Icons.search, size: 20, color: Colors.black45),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _results = []);
                      },
                    ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppColors.parchment50,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Column(children: [
              for (final place in _results)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, size: 18, color: AppColors.blaze700),
                  title: Text(place.name, style: AppText.body(size: 13.5, weight: FontWeight.w600)),
                  subtitle: place.subtitle.isEmpty
                      ? null
                      : Text(place.subtitle, style: AppText.body(size: 11, color: Colors.black45), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _select(place),
                ),
            ]),
          ),
      ],
    );
  }
}
