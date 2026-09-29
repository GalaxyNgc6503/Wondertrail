import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RevenueCat wiring.
///
/// Free: [dailyFreeRolls] rolls per day.
/// Premium (entitlement [entitlementId]): unlimited rolls + re-roll a single stop.
///
/// Where the plan is set up in RevenueCat: create an entitlement named
/// `premium` (or set `REVENUECAT_ENTITLEMENT_ID`), attach your products to
/// it, and add a paywall to the current offering.
///
/// **Testing purchases:** set `REVENUECAT_API_KEY_TEST` to your project's
/// Test Store key (Project Settings → API keys → Test Store in the
/// RevenueCat dashboard, prefixed `test_`) and leave it in `.env` during
/// development. It's checked before the platform keys below and works on
/// both iOS and Android with the same key — no sandbox Apple/Google
/// accounts needed. Purchases show a local Test Store dialog (pick
/// Successful/Failed/Cancel by hand) and update real entitlements you can
/// see on the RevenueCat dashboard. **Never ship a release build configured
/// with a `test_` key** — swap back to the real platform key for release.
class MonetizationService {
  MonetizationService._();
  static final MonetizationService instance = MonetizationService._();

  static const dailyFreeRolls = 3;

  /// True while the user holds the premium entitlement.
  final ValueNotifier<bool> isPremium = ValueNotifier(false);

  bool _configured = false;

  /// False on web/desktop or when no RevenueCat key is set — purchases can't
  /// happen there, so paywall calls explain that instead of failing silently.
  bool get canPurchase => _configured;

  String get entitlementId => dotenv.maybeGet('REVENUECAT_ENTITLEMENT_ID') ?? 'premium';

  /// Call once at startup, after `dotenv.load`. Leave [userId] null until
  /// real auth exists so RevenueCat uses an anonymous id per install —
  /// passing a shared placeholder would give everyone the same entitlement.
  Future<void> init({String? userId}) async {
    // Debug-only switch to try premium features without a store sandbox.
    if (kDebugMode && dotenv.maybeGet('REVENUECAT_DEBUG_PREMIUM') == 'true') {
      isPremium.value = true;
      return;
    }
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return;

    final testKey = dotenv.maybeGet('REVENUECAT_API_KEY_TEST');
    final key = (testKey != null && testKey.isNotEmpty)
        ? testKey
        : (Platform.isIOS
            ? dotenv.maybeGet('REVENUECAT_API_KEY_IOS')
            : dotenv.maybeGet('REVENUECAT_API_KEY_ANDROID'));
    if (key == null || key.isEmpty) {
      debugPrint('RevenueCat: no API key set for this platform — running as free tier.');
      return;
    }
    if (kDebugMode && key.startsWith('test_')) {
      debugPrint('RevenueCat: using the Test Store — never ship this key in a release build.');
    }

    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
      final config = PurchasesConfiguration(key);
      if (userId != null) config.appUserID = userId;
      await Purchases.configure(config);
      _configured = true;

      Purchases.addCustomerInfoUpdateListener(_apply);
      _apply(await Purchases.getCustomerInfo());
    } on PlatformException catch (e) {
      debugPrint('RevenueCat init failed: ${e.message}');
    }
  }

  /// Call after your own sign-in so purchases follow the account.
  Future<void> logIn(String userId) async {
    if (!_configured) return;
    final result = await Purchases.logIn(userId);
    _apply(result.customerInfo);
  }

  void _apply(CustomerInfo info) {
    isPremium.value = info.entitlements.active.containsKey(entitlementId);
  }

  /// Shows RevenueCat's paywall. Returns true if the user is premium
  /// afterwards (purchased, restored, or already was).
  Future<bool> presentPaywall() async {
    if (isPremium.value) return true;
    if (!_configured) return false;
    try {
      await RevenueCatUI.presentPaywall();
      _apply(await Purchases.getCustomerInfo());
    } on PlatformException catch (e) {
      debugPrint('Paywall failed: ${e.message}');
    }
    return isPremium.value;
  }
}

/// Tracks today's rolls for free users.
///
/// Stored on-device (per local calendar day), so it's a UX limit rather than
/// a hard one — reinstalling or clearing app data resets it. For a limit you
/// can't get around, count rolls server-side (e.g. an Appwrite Function that
/// checks the RevenueCat entitlement).
class RollQuota extends ChangeNotifier {
  static const _dateKey = 'roll_quota_date';
  static const _usedKey = 'roll_quota_used';

  int _used = 0;
  bool _loaded = false;

  bool get loaded => _loaded;
  int get used => _used;
  int get remaining => (MonetizationService.dailyFreeRolls - _used).clamp(0, MonetizationService.dailyFreeRolls);

  /// Whether a roll is allowed right now.
  bool canRoll({required bool premium}) => premium || remaining > 0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _used = prefs.getString(_dateKey) == _today() ? (prefs.getInt(_usedKey) ?? 0) : 0;
    _loaded = true;
    notifyListeners();
  }

  /// Counts one roll. Premium rolls aren't counted.
  Future<void> consume({required bool premium}) async {
    if (premium) return;
    final prefs = await SharedPreferences.getInstance();
    final today = _today();
    if (prefs.getString(_dateKey) != today) {
      await prefs.setString(_dateKey, today);
      _used = 0;
    }
    _used += 1;
    await prefs.setInt(_usedKey, _used);
    notifyListeners();
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }
}
