import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screen/build/build_screen.dart';
import 'screen/roll/roll_screen.dart';
import 'services/monetization_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  // TODO: pass the signed-in user's real id once auth is wired up — see
  // RootShell.userId below.
  await MonetizationService.instance.init();
  runApp(const WondertrailApp());
}

class WondertrailApp extends StatelessWidget {
  const WondertrailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wondertrail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.parchment50,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.blaze600,
          primary: AppColors.blaze600,
          surface: AppColors.parchment50,
        ),
      ),
      // TODO: replace with the signed-in user's real ID once auth is wired up.
      home: const RootShell(userId: 'demo-user'),
    );
  }
}

/// Bottom-nav shell between Roll (Traveller) and Build (Explorer) — the two
/// personas the app serves.
///
/// Deliberately not an IndexedStack: switching tabs rebuilds the target
/// screen fresh each time, so Build always opens on a clean map view.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.userId});

  final String userId;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screen = _index == 0 ? RollScreen(userId: widget.userId) : BuildScreen(userId: widget.userId);

    return Scaffold(
      // Each tab gets its own ScaffoldMessenger scope so SnackBars shown
      // from Roll/Build attach to that tab's own Scaffold instead of
      // bubbling up to this one. Without this, a floating SnackBar bubbles
      // up to the Scaffold below (the one with bottomNavigationBar) and
      // hits a long-standing Flutter framework bug where a floating
      // SnackBar can't lay itself out correctly alongside a
      // bottomNavigationBar ("Floating SnackBar presented off screen").
      body: ScaffoldMessenger(child: screen),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.parchment50,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.casino_outlined), selectedIcon: Icon(Icons.casino), label: 'Roll'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Build'),
        ],
      ),
    );
  }
}
