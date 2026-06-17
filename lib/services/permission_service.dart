import 'package:permission_handler/permission_handler.dart';

/// Requests every runtime permission the brief's background service
/// section calls for. Must be called and granted before BLE scanning,
/// advertising, or the foreground relay service can start.
class PermissionService {
  static Future<bool> requestAll() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.notification,
      // Required on Android 11 and below for BLE scan results to
      // return any devices at all.
      Permission.locationWhenInUse,
    ].request();

    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  static Future<bool> hasAllRequired() async {
    final results = await Future.wait([
      Permission.bluetoothScan.isGranted,
      Permission.bluetoothConnect.isGranted,
      Permission.bluetoothAdvertise.isGranted,
    ]);
    return results.every((granted) => granted);
  }
}
