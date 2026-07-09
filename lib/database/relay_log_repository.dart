import 'package:sqflite/sqflite.dart';

import '../models/identity.dart';
import 'database_helper.dart';

class RelayLogRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<bool> hasSeen(String messageId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'relay_log',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markSeen(String messageId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'relay_log',
      RelayLogEntry(messageId: messageId, firstSeen: now).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> incrementForwardCount(String messageId) async {
    final db = await _dbHelper.database;
    await db.rawUpdate(
      'UPDATE relay_log SET forward_count = forward_count + 1 WHERE message_id = ?',
      [messageId],
    );
  }

  /// THE core anti-loop rule: has this exact message_id already been
  /// forwarded to this exact peer? If true, skip it on this contact.
  Future<bool> hasForwardedToPeer(String messageId, String peerDeviceId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'relay_peer_log',
      where: 'message_id = ? AND peer_device_id = ?',
      whereArgs: [messageId, peerDeviceId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markForwardedToPeer(String messageId, String peerDeviceId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'relay_peer_log',
      RelayPeerRecord(
        messageId: messageId,
        peerDeviceId: peerDeviceId,
        forwardedAt: now,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteForMessage(String messageId) async {
    final db = await _dbHelper.database;
    await db.delete('relay_log', where: 'message_id = ?', whereArgs: [messageId]);
    await db.delete('relay_peer_log', where: 'message_id = ?', whereArgs: [messageId]);
  }
}
