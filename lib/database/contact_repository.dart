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
}
