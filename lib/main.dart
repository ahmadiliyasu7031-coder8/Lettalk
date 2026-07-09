import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Notification channels must be created before any background
  // service fires them — this is fast and local only.
  try {
    await NotificationService.instance.init();
  } catch (_) {}

  // Everything else (DB init, identity load, BLE, Uranium) is handled
  // lazily inside the Splash screen and individual screens — never here.
  // This keeps the app launch time minimal.

  runApp(const ProviderScope(child: LettalkApp()));
}

class LettalkApp extends StatelessWidget {
  const LettalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lettalk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}
