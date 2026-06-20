import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../models/outbox_message.dart';
import 'database_helper.dart';

class OutboxRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<void> insert(OutboxMessage message) async {
    final db = await _dbHelper.database;
    await db.insert('outbox', message.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<OutboxMessage>> getAllWaiting() async {
    final db = await _dbHelper.database;
    final rows = await db.query('outbox', where: 'status = ?', whereArgs: [MessageStatus.waiting]);
    return rows.map((r) => OutboxMessage.fromMap(r)).toList();
  }

  Future<List<OutboxMessage>> getWaitingFor(String recipientId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'outbox',
      where: 'recipient_id = ? AND status = ?',
      whereArgs: [recipientId, MessageStatus.waiting],
    );
    return rows.map((r) => OutboxMessage.fromMap(r)).toList();
  }

  /// All outbox entries involving a given conversation partner — used to
  /// merge into the chat thread display regardless of waiting/expired status.
  Future<List<OutboxMessage>> getForConversation(String myId, String otherId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'outbox',
      where: '(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
      whereArgs: [myId, otherId, otherId, myId],
      orderBy: 'created_at ASC',
    );
    return rows.map((r) => OutboxMessage.fromMap(r)).toList();
  }

  Future<List<OutboxMessage>> getLatestPerConversation(String myId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT o.* FROM outbox o
      WHERE o.status = ? AND (o.sender_id = ? OR o.recipient_id = ?)
        AND o.created_at = (
          SELECT MAX(o2.created_at) FROM outbox o2
          WHERE (o2.sender_id = o.sender_id AND o2.recipient_id = o.recipient_id) OR
                (o2.sender_id = o.recipient_id AND o2.recipient_id = o.sender_id)
        )
      GROUP BY CASE WHEN o.sender_id = ? THEN o.recipient_id ELSE o.sender_id END
    ''', [MessageStatus.waiting, myId, myId, myId]);
    return rows.map((r) => OutboxMessage.fromMap(r)).toList();
  }

  Future<void> markExpired(String messageId) async {
    final db = await _dbHelper.database;
    await db.update('outbox', {'status': MessageStatus.expired},
        where: 'message_id = ?', whereArgs: [messageId]);
  }

  /// Removes an outbox entry once it has been promoted into a real,
  /// encrypted message in the `messages` table.
  Future<void> remove(String messageId) async {
    final db = await _dbHelper.database;
    await db.delete('outbox', where: 'message_id = ?', whereArgs: [messageId]);
  }

  Future<int> purgeExpired() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.delete('outbox', where: 'expires_at <= ? AND status = ?', whereArgs: [now, MessageStatus.waiting]);
  }
}
