import 'package:sqflite/sqflite.dart';

import '../models/identity.dart';
import 'database_helper.dart';

class IdentityRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<Identity?> getIdentity() async {
    final db = await _dbHelper.database;
    final rows = await db.query('identity', limit: 1);
    if (rows.isEmpty) return null;
    return Identity.fromMap(rows.first);
  }

  Future<bool> hasIdentity() async {
    final identity = await getIdentity();
    return identity != null;
  }

  Future<void> saveIdentity(Identity identity) async {
    final db = await _dbHelper.database;
    await db.insert(
      'identity',
      identity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateUsername(String username) async {
    final db = await _dbHelper.database;
    await db.update(
      'identity',
      {'username': username},
      where: 'lettalk_id = (SELECT lettalk_id FROM identity LIMIT 1)',
    );
  }

  /// Logout — wipes the local identity. Per spec this is destructive
  /// and irreversible (no server backup exists to restore from).
  Future<void> clearIdentity() async {
    final db = await _dbHelper.database;
    await db.delete('identity');
  }
}
