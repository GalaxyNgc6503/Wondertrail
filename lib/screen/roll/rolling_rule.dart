/// How a Traveller wants their roll to behave. This is the Traveller's own
/// preference, set on the Roll tab — never something an Explorer
/// configures when publishing a trail (see the product decision in the
/// build spec's §1).
///
/// Kept in its own file specifically so roll_screen.dart and
/// roll_chain_screen.dart can both import it without importing each other.
enum RollingRule {
  /// Picks one random published trail within radius, then walks its
  /// stops in order on every subsequent roll. Never branches.
  trail,

  /// Every roll draws uniformly from the entire cross-trail-eligible pool
  /// within radius — no preference for staying on the current trail or
  /// switching off it.
  random,

  /// Manual stop-selection UI. Honest stub for now.
  illPick;

  String get label {
    switch (this) {
      case RollingRule.trail:
        return 'Trail';
      case RollingRule.random:
        return 'Random';
      case RollingRule.illPick:
        return "I'll pick";
    }
  }
}
