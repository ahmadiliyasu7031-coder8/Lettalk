import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'database_helper.dart';

/// Generic key-value settings store backing the Settings screen:
/// scan interval (1/2/5 min), node-discovered notification toggle,
/// and mute-per-contact list.
class SettingsRepository {
  final _dbHelper = DatabaseHelper.instance;

  static const keyScanIntervalMinutes = 'scan_interval_minutes';
  static const keyNodeDiscoveredEnabled = 'node_discovered_notifications_enabled';

  Future<String?> _get(String key) async {
    final db = await _dbHelper.database;
    final rows = await db.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _set(String key, String value) async {
    final db = await _dbHelper.database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> getScanIntervalMinutes() async {
    final raw = await _get(keyScanIntervalMinutes);
    return raw != null ? int.tryParse(raw) ?? 2 : 2; // default: 2 minutes, matches the brief
  }

  Future<void> setScanIntervalMinutes(int minutes) async {
    await _set(keyScanIntervalMinutes, minutes.toString());
  }

  static const _keyLocalBleDeviceId = 'local_ble_device_id';

  /// Stable, random, per-install BLE-layer Device ID. Distinct from the
  /// user-facing Lettalk ID: this one is exchanged during the BLE
  /// handshake (item 4 of the Bluetooth brief) purely so the transport
  /// layer can address a specific device before any application-level
  /// identity has been established or gossiped.
  Future<String> getOrCreateLocalDeviceId() async {
    final existing = await _get(_keyLocalBleDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = const Uuid().v4();
    await _set(_keyLocalBleDeviceId, generated);
    return generated;
  }

  Future<bool> getNodeDiscoveredEnabled() async {
    final raw = await _get(keyNodeDiscoveredEnabled);
    return raw == 'true'; // default: off, matches the brief
  }

  Future<void> setNodeDiscoveredEnabled(bool enabled) async {
    await _set(keyNodeDiscoveredEnabled, enabled.toString());
  }
}
