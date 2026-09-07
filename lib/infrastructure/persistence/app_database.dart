import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/logging/app_logger.dart';

class AppDatabase {
  AppDatabase._(this._db);

  static const _tag = 'AppDatabase';
  static const _fileName = 'driveguard.db';
  static const _schemaVersion = 2;

  final Database _db;
  Database get db => _db;

  static AppDatabase? _instance;

  static Future<AppDatabase> open() async {
    if (_instance != null) return _instance!;
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;

    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'driveguard'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    final dbPath = p.join(dbDir.path, _fileName);

    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE diagnostic_events ADD COLUMN error_code TEXT',
            );
          }
        },
      ),
    );
    AppLogger.instance.info(_tag, 'Opened database at $dbPath');
    _instance = AppDatabase._(db);
    return _instance!;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        started_at INTEGER NOT NULL,
        operating_system TEXT NOT NULL,
        app_version TEXT NOT NULL,
        polling_interval_seconds INTEGER NOT NULL,
        ended_at INTEGER,
        ended_cleanly INTEGER NOT NULL DEFAULT 0,
        last_heartbeat_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE pre_incident_samples (
        session_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        celsius REAL NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_pre_incident_session '
      'ON pre_incident_samples(session_id, device_id, timestamp)',
    );

    await db.execute('''
      CREATE TABLE incidents (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL UNIQUE,
        detected_at INTEGER NOT NULL,
        estimated_shutdown_at INTEGER,
        startup_at INTEGER,
        classification TEXT NOT NULL,
        correlation_level TEXT NOT NULL,
        summary TEXT NOT NULL,
        primary_device_id TEXT,
        notification_shown INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE incident_device_stats (
        incident_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        last_celsius REAL,
        max_celsius REAL,
        warning_exceeded INTEGER NOT NULL DEFAULT 0,
        critical_exceeded INTEGER NOT NULL DEFAULT 0,
        critical_duration_ms INTEGER NOT NULL DEFAULT 0,
        alert_triggered INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE diagnostic_events (
        session_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        source TEXT NOT NULL,
        category TEXT NOT NULL,
        summary TEXT NOT NULL,
        raw TEXT,
        error_code TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_diag_session ON diagnostic_events(session_id)',
    );
  }

  static Future<AppDatabase> openInMemoryForTesting() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        singleInstance: false,
        onCreate: (db, version) async => _createSchema(db),
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> pruneOldSamples(DateTime before) async {
    await _db.delete(
      'pre_incident_samples',
      where: 'timestamp < ?',
      whereArgs: [before.millisecondsSinceEpoch],
    );
  }
}
