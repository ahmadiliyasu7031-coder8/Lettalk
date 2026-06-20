import 'package:flutter/material.dart';

/// Design tokens — copied 1:1 from the Lettalk mockup spec.
/// Do not introduce new colors outside this palette; the entire app
/// is dark-theme-only for MVP.
class AppColors {
  static const Color background = Color(0xFF0D1117);
  static const Color surface = Color(0xFF161B22);
  static const Color card = Color(0xFF1C2128);
  static const Color primaryGreen = Color(0xFF25D366);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color sentBubble = Color(0xFF1A4731);
  static const Color receivedBubble = Color(0xFF1C2128);
  static const Color statusGood = Color(0xFF25D366);
  static const Color statusWeak = Color(0xFFF0A500);
  static const Color statusBad = Color(0xFFDA3633);
}

/// Core protocol constants — the Uranium Protocol engine and BLE layer
/// must use these exact values. Changing them breaks interop between
/// devices running different builds, so treat them as a network contract.
class ProtocolConstants {
  // BLE advertising / service identity
  static const String lettalkServiceUuid = "0000A7F2-0000-1000-8000-00805F9B34FB";
  static const String lettalkCharacteristicUuid = "0000A7F3-0000-1000-8000-00805F9B34FB";

  // Discovery cadence
  static const Duration scanInterval = Duration(minutes: 2);
  static const Duration scanDuration = Duration(seconds: 30);

  // Routing limits
  static const int maxHopCount = 20;
  static const Duration messageTtl = Duration(days: 7);
  static const Duration killSignalTtl = Duration(hours: 48);

  // Lettalk ID format: LTK-XXXX-XXXX
  static const String lettalkIdPrefix = "LTK";
}

class MessageStatus {
  static const String sent = "sent";
  static const String relayed = "relayed";
  static const String delivered = "delivered";
  static const String killed = "killed";
  static const String waiting = "waiting"; // outbox: recipient's public key not yet known
  static const String expired = "expired"; // outbox: 7-day TTL passed before resolving
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryGreen,
        surface: AppColors.surface,
        background: AppColors.background,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      cardColor: AppColors.card,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textPrimary),
        bodySmall: TextStyle(color: AppColors.textSecondary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primaryGreen,
        unselectedItemColor: AppColors.textSecondary,
      ),
    );
  }
}
