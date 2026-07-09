import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../models/message.dart';
import 'database_helper.dart';

class MessageRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<void> insertMessage(LettalkMessage message) async {
    final db = await _dbHelper.database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore, // never overwrite a message we already have
    );
  }

  Future<LettalkMessage?> getMessage(String messageId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LettalkMessage.fromMap(rows.first);
  }

  Future<bool> hasMessage(String messageId) async {
    final m = await getMessage(messageId);
    return m != null;
  }

  /// All non-expired messages this device is currently carrying
  /// (as sender, recipient, or pure relay) — this is the "relay table"
  /// exchanged with peers during the Uranium Protocol handshake.
  Future<List<LettalkMessage>> getCarriedMessages() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'messages',
      where: 'expires_at > ? AND status != ?',
      whereArgs: [now, MessageStatus.killed],
    );
    return rows.map((r) => LettalkMessage.fromMap(r)).toList();
  }

  /// Direct conversation thread with a given contact (by Lettalk ID),
  /// excludes kill signals which are never shown in the UI.
  Future<List<LettalkMessage>> getConversation(String myId, String otherId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'messages',
      where:
          '((sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)) AND is_kill_signal = 0',
      whereArgs: [myId, otherId, otherId, myId],
      orderBy: 'created_at ASC',
    );
    return rows.map((r) => LettalkMessage.fromMap(r)).toList();
  }

  /// Latest message per conversation partner, for the Chats home screen.
  Future<List<LettalkMessage>> getLatestPerConversation(String myId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT m.* FROM messages m
      WHERE m.is_kill_signal = 0
        AND (m.sender_id = ? OR m.recipient_id = ?)
        AND m.created_at = (
          SELECT MAX(m2.created_at) FROM messages m2
          WHERE m2.is_kill_signal = 0 AND (
            (m2.sender_id = m.sender_id AND m2.recipient_id = m.recipient_id) OR
            (m2.sender_id = m.recipient_id AND m2.recipient_id = m.sender_id)
          )
        )
      GROUP BY CASE WHEN m.sender_id = ? THEN m.recipient_id ELSE m.sender_id END
      ORDER BY m.created_at DESC
    ''', [myId, myId, myId]);
    return rows.map((r) => LettalkMessage.fromMap(r)).toList();
  }

  Future<void> updateStatus(String messageId, String status) async {
    final db = await _dbHelper.database;
    await db.update(
      'messages',
      {'status': status},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateHopCount(String messageId, int hopCount) async {
    final db = await _dbHelper.database;
    await db.update(
      'messages',
      {'hop_count': hopCount},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Used by the Kill Signal handler — deletes the target message's
  /// content entirely from this node, satisfying "all copies removed".
  Future<void> deleteMessage(String messageId) async {
    final db = await _dbHelper.database;
    await db.delete('messages', where: 'message_id = ?', whereArgs: [messageId]);
  }

  /// Purges anything past its TTL — called on every scan cycle.
  Future<int> purgeExpired() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.delete('messages', where: 'expires_at <= ?', whereArgs: [now]);
  }

  Future<int> countSent(String myId) async {
    final db = await _dbHelper.database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as c FROM messages WHERE sender_id = ? AND is_kill_signal = 0',
      [myId],
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<int> countReceived(String myId) async {
    final db = await _dbHelper.database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as c FROM messages WHERE recipient_id = ? AND status = ? AND is_kill_signal = 0',
      [myId, MessageStatus.delivered],
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }
}
