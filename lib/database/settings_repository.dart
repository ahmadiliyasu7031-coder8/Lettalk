import 'package:sqflite/sqflite.dart';

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

  Future<bool> getNodeDiscoveredEnabled() async {
    final raw = await _get(keyNodeDiscoveredEnabled);
    return raw == 'true'; // default: off, matches the brief
  }

  Future<void> setNodeDiscoveredEnabled(bool enabled) async {
    await _set(keyNodeDiscoveredEnabled, enabled.toString());
  }
}
