import 'package:permission_handler/permission_handler.dart';

/// Permission helper. All methods are non-throwing — they return booleans
/// rather than throwing on denial so callers never crash when a user
/// denies a permission.
class PermissionService {
  /// Request all permissions needed for the full Uranium engine.
  /// Returns true if all critical permissions (BT scan + connect) are granted.
  static Future<bool> requestAll() async {
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.notification,
        Permission.locationWhenInUse, // required on Android 11 and below for BLE scan
      ].request();

      return (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
          (statuses[Permission.bluetoothConnect]?.isGranted ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Check (without asking) whether Bluetooth permissions are already granted.
  static Future<bool> hasBluetoothPermissions() async {
    try {
      return await Permission.bluetoothScan.isGranted &&
          await Permission.bluetoothConnect.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Check whether Bluetooth hardware is currently enabled on the device.
  /// Returns false if BT is off, missing, or the check itself fails — the
  /// caller should treat any false as "BT not available right now".
  static Future<bool> isBluetoothOn() async {
    try {
      final status = await Permission.bluetooth.serviceStatus;
      return status.isEnabled;
    } catch (_) {
      return false;
    }
  }
}
