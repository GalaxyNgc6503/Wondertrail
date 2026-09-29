import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../models/destination.dart';

final _distance = Distance();

double metersBetween(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b);

/// A generated trail: ordered stops, plus which of them the user pinned as
/// Must Visit (those are never swapped out by a re-roll).
class RolledTrail {
  const RolledTrail({required this.stops, required this.mustIds});

  final List<Destination> stops;
  final Set<String> mustIds;

  bool isMust(int index) => mustIds.contains(stops[index].id);

  RolledTrail replaceAt(int index, Destination replacement) {
    final next = [...stops]..[index] = replacement;
    return RolledTrail(stops: next, mustIds: mustIds);
  }

  /// Straight-line metres from each stop to the next (length = stops - 1).
  List<double> get legMeters => [
        for (var i = 1; i < stops.length; i++) metersBetween(stops[i - 1].location, stops[i].location),
      ];

  double get totalMeters => legMeters.fold(0.0, (a, b) => a + b);

  int get visitMinutes => stops.fold(0, (sum, s) => sum + s.visitMinutes);

  /// Walking at ~5 km/h, on straight-line distance (a floor, not a promise).
  int get walkMinutes => (totalMeters / 1000 * 12).round();

  int get totalMinutes => visitMinutes + walkMinutes;
}

/// Builds spontaneous-but-practical trails.
///
/// Must Visit stops keep the order the user gave them. Everything else is
/// chosen by inserting nearby destinations where they add the least
/// walking — but the pick is randomised among the best few so each roll
/// feels different, and stops that repeat a category already in the trail
/// are penalised so the route stays varied.
class TrailRoller {
  TrailRoller({Random? random}) : _rng = random ?? Random();

  final Random _rng;

  /// How many of the best-ranked candidates a roll picks between.
  static const _pickFrom = 4;

  /// Extra cost (as a fraction) per stop of the same category already in the trail.
  static const _repeatPenalty = 0.35;

  /// [pool] is every destination in the area (Must Visit ones included).
  /// [stopCount] is the desired total, which is raised if needed so a roll
  /// always adds at least one stop beyond the Must Visits.
  RolledTrail roll({
    required List<Destination> pool,
    required List<Destination> mustVisit,
    required int stopCount,
    LatLng? anchor,
  }) {
    final mustIds = mustVisit.map((d) => d.id).toSet();
    final route = [...mustVisit];
    final candidates = pool.where((d) => !mustIds.contains(d.id)).toList();

    final target = min(max(stopCount, mustVisit.length + 1), mustVisit.length + candidates.length);

    // Nothing pinned: start from somewhere close to the centre of the area.
    if (route.isEmpty && candidates.isNotEmpty) {
      final origin = anchor;
      if (origin != null) {
        candidates.sort((a, b) => metersBetween(origin, a.location).compareTo(metersBetween(origin, b.location)));
        final seed = candidates.removeAt(_weightedIndex(min(_pickFrom, candidates.length)));
        route.add(seed);
      } else {
        route.add(candidates.removeAt(_rng.nextInt(candidates.length)));
      }
    }

    while (route.length < target && candidates.isNotEmpty) {
      final scored = <_Insertion>[
        for (final c in candidates) _bestInsertion(route, c),
      ]..sort((a, b) => a.cost.compareTo(b.cost));

      final chosen = scored[_weightedIndex(min(_pickFrom, scored.length))];
      route.insert(chosen.position, chosen.destination);
      candidates.removeWhere((c) => c.id == chosen.destination.id);
    }

    return RolledTrail(stops: route, mustIds: mustIds);
  }

  /// Swaps the stop at [index] for another destination from [pool] that fits
  /// between its neighbours, leaving every other stop untouched. Returns
  /// null for Must Visit stops or when nothing else is available.
  ///
  /// [exclude] lists ids already tried for this slot; it's ignored if that
  /// would leave nothing to pick from.
  Destination? rerollCandidate({
    required RolledTrail trail,
    required int index,
    required List<Destination> pool,
    Set<String> exclude = const {},
  }) {
    if (trail.isMust(index)) return null;

    final inTrail = trail.stops.map((s) => s.id).toSet();
    var candidates = pool.where((d) => !inTrail.contains(d.id) && !exclude.contains(d.id)).toList();
    if (candidates.isEmpty) {
      candidates = pool.where((d) => !inTrail.contains(d.id)).toList();
    }
    if (candidates.isEmpty) return null;

    final others = [...trail.stops]..removeAt(index);
    final prev = index > 0 ? trail.stops[index - 1].location : null;
    final next = index < trail.stops.length - 1 ? trail.stops[index + 1].location : null;

    final scored = <MapEntry<Destination, double>>[
      for (final c in candidates)
        MapEntry(c, _slotCost(c, prev, next) * _categoryFactor(c, others)),
    ]..sort((a, b) => a.value.compareTo(b.value));

    return scored[_weightedIndex(min(_pickFrom, scored.length))].key;
  }

  double _slotCost(Destination c, LatLng? prev, LatLng? next) {
    var cost = 0.0;
    if (prev != null) cost += metersBetween(prev, c.location);
    if (next != null) cost += metersBetween(c.location, next);
    return cost;
  }

  _Insertion _bestInsertion(List<Destination> route, Destination c) {
    var bestPos = 0;
    var bestCost = double.infinity;

    for (var pos = 0; pos <= route.length; pos++) {
      final double added;
      if (route.isEmpty) {
        added = 0;
      } else if (pos == 0) {
        added = metersBetween(c.location, route.first.location);
      } else if (pos == route.length) {
        added = metersBetween(route.last.location, c.location);
      } else {
        final a = route[pos - 1].location;
        final b = route[pos].location;
        added = metersBetween(a, c.location) + metersBetween(c.location, b) - metersBetween(a, b);
      }
      if (added < bestCost) {
        bestCost = added;
        bestPos = pos;
      }
    }

    return _Insertion(c, bestPos, bestCost * _categoryFactor(c, route));
  }

  double _categoryFactor(Destination c, List<Destination> route) {
    final repeats = route.where((s) => s.category == c.category).length;
    return 1 + _repeatPenalty * repeats;
  }

  /// Rank 0 is the likeliest; weights fall off as 1, 1/2, 1/3…
  int _weightedIndex(int count) {
    if (count <= 1) return 0;
    final weights = [for (var i = 0; i < count; i++) 1 / (i + 1)];
    var roll = _rng.nextDouble() * weights.fold(0.0, (a, b) => a + b);
    for (var i = 0; i < count; i++) {
      roll -= weights[i];
      if (roll <= 0) return i;
    }
    return count - 1;
  }
}

class _Insertion {
  const _Insertion(this.destination, this.position, this.cost);
  final Destination destination;
  final int position;
  final double cost;
}
