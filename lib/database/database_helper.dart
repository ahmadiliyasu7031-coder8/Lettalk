import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Single source of truth for the local SQLite schema.
/// Every table here is local-only — there is no server and no sync.
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'lettalk.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Users / Contacts
    await db.execute('''
      CREATE TABLE contacts (
        lettalk_id TEXT PRIMARY KEY,
        username TEXT,
        public_key TEXT,
        last_seen INTEGER
      );
    ''');

    // Messages
    await db.execute('''
      CREATE TABLE messages (
        message_id TEXT PRIMARY KEY,
        sender_id TEXT,
        recipient_id TEXT,
        content TEXT,
        status TEXT,
        created_at INTEGER,
        expires_at INTEGER,
        is_kill_signal INTEGER DEFAULT 0,
        target_message_id TEXT,
        hop_count INTEGER DEFAULT 0
      );
    ''');

    // Relay Log — message-level: have we seen / are we carrying this one
    await db.execute('''
      CREATE TABLE relay_log (
        message_id TEXT PRIMARY KEY,
        first_seen INTEGER,
        forward_count INTEGER DEFAULT 0
      );
    ''');

    // Relay peer record — peer-level: who have we already forwarded
    // a given message_id to, so we never forward it twice to the same peer.
    await db.execute('''
      CREATE TABLE relay_peer_log (
        message_id TEXT,
        peer_device_id TEXT,
        forwarded_at INTEGER,
        PRIMARY KEY (message_id, peer_device_id)
      );
    ''');

    // Local Identity (single row table — one identity per device)
    await db.execute('''
      CREATE TABLE identity (
        lettalk_id TEXT PRIMARY KEY,
        username TEXT,
        private_key TEXT,
        public_key TEXT,
        created_at INTEGER
      );
    ''');

    // Network strength snapshots, feeds the "last 1 hour" graph
    // on the Network Details screen.
    await db.execute('''
      CREATE TABLE network_snapshots (
        timestamp INTEGER PRIMARY KEY,
        nearby_count INTEGER,
        avg_rssi INTEGER,
        strength_pct INTEGER
      );
    ''');

    // Generic key-value settings store (scan interval, notification
    // toggles, mute list, etc.) — small enough not to need its own
    // typed table per setting.
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');

    // Outbox — messages composed before the recipient's public key was
    // known. Stored in PLAINTEXT, local to this device only. Never
    // exchanged with peers in this form. Once the recipient's public
    // key becomes known (direct encounter or identity gossip), these
    // get encrypted and promoted into the `messages` table.
    await db.execute('''
      CREATE TABLE outbox (
        message_id TEXT PRIMARY KEY,
        sender_id TEXT,
        recipient_id TEXT,
        plaintext_content TEXT,
        created_at INTEGER,
        expires_at INTEGER,
        status TEXT DEFAULT 'waiting'
      );
    ''');
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
