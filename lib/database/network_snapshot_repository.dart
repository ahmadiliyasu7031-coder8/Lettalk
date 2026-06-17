import 'database_helper.dart';

class NetworkSnapshot {
  final int timestamp;
  final int nearbyCount;
  final int avgRssi;
  final int strengthPct;

  NetworkSnapshot({
    required this.timestamp,
    required this.nearbyCount,
    required this.avgRssi,
    required this.strengthPct,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp,
        'nearby_count': nearbyCount,
        'avg_rssi': avgRssi,
        'strength_pct': strengthPct,
      };

  factory NetworkSnapshot.fromMap(Map<String, dynamic> map) => NetworkSnapshot(
        timestamp: map['timestamp'] as int,
        nearbyCount: map['nearby_count'] as int,
        avgRssi: map['avg_rssi'] as int,
        strengthPct: map['strength_pct'] as int,
      );
}

class NetworkSnapshotRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<void> recordSnapshot(NetworkSnapshot snapshot) async {
    final db = await _dbHelper.database;
    await db.insert('network_snapshots', snapshot.toMap());
    // Keep only the last 24 hours of history — this is a rolling
    // local diagnostic, not a permanent record.
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    await db.delete(
      'network_snapshots',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  Future<List<NetworkSnapshot>> getLastHour() async {
    final db = await _dbHelper.database;
    final cutoff =
        DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    final rows = await db.query(
      'network_snapshots',
      where: 'timestamp >= ?',
      whereArgs: [cutoff],
      orderBy: 'timestamp ASC',
    );
    return rows.map((r) => NetworkSnapshot.fromMap(r)).toList();
  }

  Future<NetworkSnapshot?> getLatest() async {
    final db = await _dbHelper.database;
    final rows = await db.query('network_snapshots', orderBy: 'timestamp DESC', limit: 1);
    if (rows.isEmpty) return null;
    return NetworkSnapshot.fromMap(rows.first);
  }
}
