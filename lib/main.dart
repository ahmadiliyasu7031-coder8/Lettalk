import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'database/database_helper.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Touch the DB once at startup so the schema is created before any
  // screen tries to read from it.
  await DatabaseHelper.instance.database;
  await NotificationService.instance.init();

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
      themeMode: ThemeMode.dark, // Dark theme only, per MVP scope
      home: const SplashScreen(),
    );
  }
}
