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

  // --- BLE Manager / packet-layer contract -------------------------------
  // Every device on the mesh must agree on these or the handshake will
  // (intentionally) refuse to proceed. Bump protocolVersion on any
  // wire-incompatible change to BlePacket or WireMessage.
  static const int protocolVersion = 1;
  static const List<String> supportedFeatures = ['sync', 'relay', 'kill_signal'];

  // Conservative default below the minimum negotiated BLE MTU (23 bytes
  // overhead reserved) so packets fit unfragmented-by-the-stack on
  // virtually every Android device without negotiating ATT MTU up front.
  static const int blePacketMtu = 180;

  static const int packetMaxRetries = 4;
  static const Duration packetAckTimeout = Duration(seconds: 5);
  static const Duration handshakeTimeout = Duration(seconds: 8);
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration syncReplyTimeout = Duration(seconds: 15);

  // Reconnection backoff: 2^attempt seconds, capped, give up after this
  // many consecutive failures (until the peer is rediscovered fresh).
  static const int maxReconnectAttempts = 6;
  static const int maxReconnectBackoffSeconds = 60;

  // How long a continuous-scan window lasts before it's restarted.
  // flutter_blue_plus (and Android itself) don't reliably sustain a
  // single indefinite scan call, so "continuous scanning" is implemented
  // as back-to-back windows with no gap rather than one unbounded call.
  static const Duration continuousScanWindow = Duration(seconds: 25);

  // How often the advertising watchdog checks that the peripheral is
  // still actually advertising, and restarts it if Android silently
  // stopped it (OEM battery optimizations, radio resets, etc.).
  static const Duration advertisingWatchdogInterval = Duration(seconds: 20);

  // --- Hardening pass additions -------------------------------------------
  // Defense-in-depth timeout wrapped around every raw BLE write/notify
  // call. Per-fragment ACK waits are already bounded by packetAckTimeout,
  // but that only helps if the underlying platform call itself returns;
  // this guards against a platform call that never completes at all.
  static const Duration rawSendTimeout = Duration(seconds: 8);

  // A per-central/per-connection reassembly channel that receives no
  // traffic for this long is assumed abandoned (interrupted transfer,
  // central vanished without a clean disconnect, etc.) and is torn down
  // to release its buffer and avoid corrupting a future, unrelated
  // transfer with stale partial bytes.
  static const Duration channelIdleTimeout = Duration(minutes: 2);
  static const Duration idleChannelSweepInterval = Duration(seconds: 30);

  // How often BleManager polls whether the Bluetooth radio itself is
  // still on, so it can pause cleanly (rather than error-loop) when the
  // user disables Bluetooth, and resume automatically when it's back.
  static const Duration bluetoothStatePollInterval = Duration(seconds: 5);

  // If no scan cycle has produced so much as a log line in this long,
  // the scan loop is presumed stalled (some OEM stacks silently wedge
  // the scanner) and is force-restarted from scratch.
  static const Duration scanStallThreshold = Duration(seconds: 90);
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
