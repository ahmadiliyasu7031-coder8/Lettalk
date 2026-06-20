import 'package:sqflite/sqflite.dart';

import '../models/contact.dart';
import 'database_helper.dart';

class ContactRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<List<Contact>> getAllContacts() async {
    final db = await _dbHelper.database;
    final rows = await db.query('contacts', orderBy: 'last_seen DESC');
    return rows.map((r) => Contact.fromMap(r)).toList();
  }

  Future<Contact?> getContact(String lettalkId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'contacts',
      where: 'lettalk_id = ?',
      whereArgs: [lettalkId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Contact.fromMap(rows.first);
  }

  Future<void> upsertContact(Contact contact) async {
    final db = await _dbHelper.database;
    await db.insert(
      'contacts',
      contact.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateLastSeen(String lettalkId, int timestamp) async {
    final db = await _dbHelper.database;
    await db.update(
      'contacts',
      {'last_seen': timestamp},
      where: 'lettalk_id = ?',
      whereArgs: [lettalkId],
    );
  }

  Future<void> deleteContact(String lettalkId) async {
    final db = await _dbHelper.database;
    await db.delete('contacts', where: 'lettalk_id = ?', whereArgs: [lettalkId]);
  }

  /// Identity gossip — every sync exchanges a small slice of "identities
  /// I know about" so public keys can propagate through the mesh even
  /// between two devices that have never directly met. This is how a
  /// queued outbox message can eventually find a route to encryption
  /// without the sender ever meeting the recipient in person.
  Future<List<Map<String, dynamic>>> exportForGossip({int limit = 50}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'contacts',
      where: 'public_key IS NOT NULL',
      orderBy: 'last_seen DESC',
      limit: limit,
    );
    return rows;
  }

  /// Merges identities learned from a peer during sync. Never downgrades
  /// a contact we already know more recently about, and never overwrites
  /// a known public key with a null one.
  Future<void> mergeFromGossip(List<Map<String, dynamic>> identities) async {
    final db = await _dbHelper.database;
    for (final raw in identities) {
      final lettalkId = raw['lettalk_id'] as String?;
      final publicKey = raw['public_key'] as String?;
      if (lettalkId == null || publicKey == null) continue;

      final existing = await getContact(lettalkId);
      if (existing == null) {
        await upsertContact(Contact(
          lettalkId: lettalkId,
          username: raw['username'] as String? ?? lettalkId,
          publicKey: publicKey,
          lastSeen: raw['last_seen'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ));
      } else if (existing.publicKey == null) {
        // We knew the ID (e.g. from an outbox draft) but not the key yet.
        await upsertContact(existing.copyWith(
          publicKey: publicKey,
          username: raw['username'] as String? ?? existing.username,
        ));
      }
    }
  }
}
