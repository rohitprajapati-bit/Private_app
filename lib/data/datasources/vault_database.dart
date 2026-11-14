import 'package:sqflite/sqflite.dart';

import '../models/media_record.dart';

class VaultDatabase {
  VaultDatabase(this._path);

  final String _path;
  Database? _db;

  Future<Database> get _database async => _db ??= await openDatabase(
    _path,
    version: 2,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
      // Overwrite deleted rows (wrapped file keys, encrypted names) instead of leaving them
      // in free pages. This pragma returns a row, so it must go through rawQuery: iOS sqflite
      // fails `execute` for statements that return results.
      await db.rawQuery('PRAGMA secure_delete = ON');
    },
    onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE albums (
          id TEXT PRIMARY KEY,
          name_enc BLOB NOT NULL,
          created_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE media (
          id TEXT PRIMARY KEY,
          type INTEGER NOT NULL,
          name_enc BLOB NOT NULL,
          ext TEXT NOT NULL,
          wrapped_key BLOB NOT NULL,
          size INTEGER NOT NULL,
          imported_at INTEGER NOT NULL,
          committed INTEGER NOT NULL DEFAULT 0,
          album_id TEXT REFERENCES albums(id) ON DELETE SET NULL,
          duration_ms INTEGER,
          width INTEGER,
          height INTEGER,
          shared_from TEXT
        )''');
      await db.execute('CREATE INDEX media_album ON media(album_id)');
    },
    onUpgrade: (db, from, _) async {
      // v2: items received from a paired admin device carry that device's id.
      if (from < 2) await db.execute('ALTER TABLE media ADD COLUMN shared_from TEXT');
    },
  );

  Future<void> insertPending(MediaRecord record) async =>
      (await _database).insert('media', record.toRow());

  Future<void> commit(String id) async =>
      (await _database).update('media', {'committed': 1}, where: 'id = ?', whereArgs: [id]);

  Future<List<MediaRecord>> committedMedia() async {
    final rows = await (await _database).query('media', where: 'committed = 1');
    return rows.map(MediaRecord.fromRow).toList();
  }

  Future<List<String>> pendingIds() async {
    final rows = await (await _database).query('media', columns: ['id'], where: 'committed = 0');
    return rows.map((r) => r['id']! as String).toList();
  }

  /// The owner's own items (what an admin device shares).
  Future<List<MediaRecord>> ownCommittedMedia() async {
    final rows = await (await _database).query('media', where: 'committed = 1 AND shared_from IS NULL');
    return rows.map(MediaRecord.fromRow).toList();
  }

  /// Ids of items received from [deviceId], or from any device when null.
  Future<Set<String>> sharedIds([String? deviceId]) async {
    final rows = await (await _database).query(
      'media',
      columns: ['id'],
      where: deviceId == null ? 'shared_from IS NOT NULL' : 'shared_from = ?',
      whereArgs: deviceId == null ? null : [deviceId],
    );
    return rows.map((r) => r['id']! as String).toSet();
  }

  Future<Set<String>> allMediaIds() async {
    final rows = await (await _database).query('media', columns: ['id']);
    return rows.map((r) => r['id']! as String).toSet();
  }

  Future<MediaRecord?> media(String id) async {
    final rows = await (await _database).query('media', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : MediaRecord.fromRow(rows.single);
  }

  Future<void> deleteMedia(Iterable<String> ids) async {
    final db = await _database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete('media', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<void> moveMedia(Iterable<String> ids, String? albumId) async {
    final db = await _database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update('media', {'album_id': albumId}, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<List<AlbumRecord>> albums() async {
    final rows = await (await _database).query('albums', orderBy: 'created_at');
    return rows.map(AlbumRecord.fromRow).toList();
  }

  Future<void> insertAlbum(AlbumRecord album) async => (await _database).insert('albums', album.toRow());

  Future<void> renameAlbum(String id, List<int> encryptedName) async =>
      (await _database).update('albums', {'name_enc': encryptedName}, where: 'id = ?', whereArgs: [id]);

  /// Media rows fall back to no album via ON DELETE SET NULL.
  Future<void> deleteAlbum(String id) async =>
      (await _database).delete('albums', where: 'id = ?', whereArgs: [id]);

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
