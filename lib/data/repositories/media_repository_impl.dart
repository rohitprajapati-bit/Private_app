import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/encryption/aead.dart';
import '../../core/encryption/chunked_cipher.dart';
import '../../core/errors/failures.dart';
import '../../core/security/key_hierarchy.dart';
import '../../core/security/vault_session.dart';
import '../../core/storage/vault_paths.dart';
import '../../core/utilities/bytes.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/vault_library.dart';
import '../../domain/repositories/media_repository.dart';
import '../../platform/platform_services.dart';
import '../datasources/media_stream_server.dart';
import '../datasources/vault_database.dart';
import '../models/media_record.dart';

class MediaRepositoryImpl implements MediaRepository {
  MediaRepositoryImpl({
    required VaultDatabase database,
    required VaultPaths paths,
    required KeyHierarchy keys,
    required ChunkedCipher cipher,
    required VaultSession session,
    required PlatformServices platform,
    required MediaStreamServer server,
  }) : _db = database,
       _paths = paths,
       _keys = keys,
       _cipher = cipher,
       _session = session,
       _platform = platform,
       _server = server;

  final VaultDatabase _db;
  final VaultPaths _paths;
  final KeyHierarchy _keys;
  final ChunkedCipher _cipher;
  final VaultSession _session;
  final PlatformServices _platform;
  final MediaStreamServer _server;

  static const _thumbCacheSize = 300;
  final _thumbCache = <String, Uint8List>{};

  /// Recovery runs once per unlock, before the first listing, so it never races an import.
  bool _recovered = false;

  @override
  Future<VaultLibrary> load() async {
    if (!_recovered) {
      await recover();
      _recovered = true;
    }
    final masterKey = _session.masterKey;
    final items = <MediaItem>[];
    for (final record in await _db.committedMedia()) {
      items.add(
        MediaItem(
          id: record.id,
          type: MediaType.values[record.type],
          name: await _keys.decryptText(masterKey, record.encryptedName, nameContext(record.id)),
          extension: record.extension,
          sizeBytes: record.sizeBytes,
          importedAt: DateTime.fromMillisecondsSinceEpoch(record.importedAt),
          albumId: record.albumId,
          duration: record.durationMs == null ? null : Duration(milliseconds: record.durationMs!),
          width: record.width,
          height: record.height,
          sharedFrom: record.sharedFrom,
        ),
      );
    }
    final albums = <Album>[];
    for (final record in await _db.albums()) {
      albums.add(
        Album(
          id: record.id,
          name: await _keys.decryptText(masterKey, record.encryptedName, _albumContext(record.id)),
          createdAt: DateTime.fromMillisecondsSinceEpoch(record.createdAt),
        ),
      );
    }
    return VaultLibrary(items: items, albums: albums);
  }

  @override
  Stream<ImportProgress> import(List<ImportSource> sources, MediaType type, {String? albumId}) {
    final controller = StreamController<ImportProgress>();
    Future<void> run() async {
      var failed = 0;
      final imported = <String>[];
      try {
        for (var i = 0; i < sources.length; i++) {
          var lastReported = 0.0;
          ImportProgress progress(int completed, double fraction) => ImportProgress(
            completed: completed,
            total: sources.length,
            currentFraction: fraction,
            failed: failed,
            importedPaths: List.unmodifiable(imported),
          );
          try {
            await _importOne(sources[i], type, albumId, (fraction) {
              if (fraction - lastReported < 0.02 && fraction < 1) return;
              lastReported = fraction;
              controller.add(progress(i, fraction));
            });
            imported.add(sources[i].path);
          } on Object {
            failed++;
          }
          controller.add(progress(i + 1, 0));
        }
      } finally {
        // Always close, or the progress dialog would wait forever.
        await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }

  /// One import transaction:
  ///  1. insert a *pending* row (wrapped key + encrypted name)
  ///  2. encrypt into tmp/{id}.media.part (+ thumbnail), flushed to disk
  ///  3. atomically rename into media/ and thumbs/
  ///  4. mark the row committed
  ///  5. delete the picker's plaintext copy
  /// A crash before step 4 leaves a pending row and/or .part files that [recover] removes.
  Future<void> _importOne(ImportSource item, MediaType type, String? albumId, void Function(double) onProgress) async {
    final path = item.path;
    // Own copy: locking wipes the session's buffer, which must not corrupt a half-written record.
    final masterKey = Uint8List.fromList(_session.masterKey);
    final source = File(path);
    final id = randomId();
    final fileKey = randomBytes(Aead.keyLength);
    final isVideo = type == MediaType.video;
    final extension = _extensionOf(path, isVideo);
    final mediaPart = _paths.partFile(id, 'media');
    final thumbPart = _paths.partFile(id, 'thumb');
    try {
      final info = await _platform.mediaInfo(path, isVideo: isVideo, maxPixels: AppConstants.thumbnailMaxPixels);
      await _db.insertPending(
        MediaRecord(
          id: id,
          type: type.index,
          encryptedName: await _keys.encryptText(masterKey, item.name, nameContext(id)),
          extension: extension,
          wrappedKey: await _keys.wrapFileKey(masterKey, fileKey, id),
          sizeBytes: await source.length(),
          importedAt: DateTime.now().millisecondsSinceEpoch,
          committed: false,
          albumId: albumId,
          durationMs: info?.duration?.inMilliseconds,
          width: info?.width,
          height: info?.height,
        ),
      );

      await _cipher.encryptFile(
        source: source,
        target: mediaPart,
        key: fileKey,
        fileId: id,
        onProgress: (done, total) {
          // Abort (and roll back) if the vault locked while this file was encrypting.
          if (!_session.isUnlocked) throw const VaultLocked();
          onProgress(total == 0 ? 1 : done / total);
        },
      );
      final thumbnail = info?.thumbnail;
      if (thumbnail != null) {
        await _cipher.encryptBytes(data: thumbnail, target: thumbPart, key: fileKey, fileId: thumbId(id));
        await thumbPart.rename(_paths.thumbFile(id).path);
      }
      if (!_session.isUnlocked) throw const VaultLocked();
      await mediaPart.rename(_paths.mediaFile(id).path);
      await _db.commit(id);
    } on Object {
      await _deleteQuietly([mediaPart, thumbPart, _paths.mediaFile(id), _paths.thumbFile(id)]);
      try {
        await _db.deleteMedia([id]);
      } on Object {
        // A leftover pending row is removed by recover() on the next unlock.
      }
      rethrow;
    } finally {
      wipe(fileKey);
      wipe(masterKey);
      // Never leave the picker's plaintext copy behind, whether the import succeeded or not.
      if (await VaultPaths.isPickerCopy(path)) await _deleteQuietly([source]);
    }
  }

  @override
  Future<void> recover() async {
    await _paths.clearTemp();
    final pending = await _db.pendingIds();
    for (final id in pending) {
      await _deleteQuietly([_paths.mediaFile(id), _paths.thumbFile(id)]);
    }
    await _db.deleteMedia(pending);

    final known = await _db.allMediaIds();
    for (final dir in [_paths.media, _paths.thumbs]) {
      await for (final entity in dir.list()) {
        if (entity is File && !known.contains(p.basenameWithoutExtension(entity.path))) {
          await _deleteQuietly([entity]);
        }
      }
    }
    final missing = [
      for (final id in known)
        if (!await _paths.mediaFile(id).exists()) id,
    ];
    await _db.deleteMedia(missing);
  }

  @override
  Future<Uint8List> thumbnail(MediaItem item) async {
    final cached = _thumbCache.remove(item.id);
    if (cached != null) return _thumbCache[item.id] = cached;
    final file = _paths.thumbFile(item.id);
    if (!await file.exists()) throw const StorageFailure('No preview.');
    final bytes = await _withFileKey(item.id, (key) => _cipher.decryptToMemory(source: file, key: key, fileId: thumbId(item.id)));
    _thumbCache[item.id] = bytes;
    if (_thumbCache.length > _thumbCacheSize) _thumbCache.remove(_thumbCache.keys.first);
    return bytes;
  }

  @override
  Future<Uint8List> photoBytes(MediaItem item) async {
    final original = await _decryptOriginal(item);
    return await _platform.transcodeForDisplay(original) ?? original;
  }

  @override
  Future<Uri> videoUri(MediaItem item) async {
    final record = await _db.media(item.id);
    if (record == null) throw const StorageFailure('Item not found.');
    final fileKey = await _keys.unwrapFileKey(_session.masterKey, record.wrappedKey, item.id);
    return _server.register(
      id: item.id,
      file: _paths.mediaFile(item.id),
      fileKey: fileKey,
      mimeType: item.mimeType,
      extension: item.extension,
    );
  }

  @override
  void releaseVideo(MediaItem item) => _server.unregister(item.id);

  @override
  Future<int> export(List<MediaItem> items) => _session.withoutAutoLock(() async {
    _requireOwned(items);
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      throw const StorageFailure('Permission to save to the gallery was denied.');
    }
    var saved = 0;
    for (final item in items) {
      try {
        if (item.isVideo) {
          final temp = _paths.exportFile(item.id, item.extension);
          try {
            await _withFileKey(
              item.id,
              (key) => _cipher.decryptToFile(source: _paths.mediaFile(item.id), target: temp, key: key, fileId: item.id),
            );
            await Gal.putVideo(temp.path);
          } finally {
            await _deleteQuietly([temp]);
          }
        } else {
          await Gal.putImageBytes(await _decryptOriginal(item), name: item.name);
        }
        saved++;
      } on Object {
        // Skip this item; the caller reports how many succeeded.
      }
    }
    return saved;
  });

  @override
  Future<void> delete(List<MediaItem> items) async {
    _requireOwned(items);
    // Deleting the row destroys the wrapped file key first: from that moment the ciphertext
    // is unrecoverable even if flash storage keeps old blocks around.
    await _db.deleteMedia(items.map((i) => i.id));
    for (final item in items) {
      _thumbCache.remove(item.id);
      _server.unregister(item.id);
      await _deleteQuietly([_paths.mediaFile(item.id), _paths.thumbFile(item.id)]);
    }
  }

  @override
  Future<void> move(List<MediaItem> items, String? albumId) async {
    _requireOwned(items);
    await _db.moveMedia(items.map((i) => i.id), albumId);
  }

  @override
  Future<Album> createAlbum(String name) async {
    final id = randomId();
    final now = DateTime.now();
    await _db.insertAlbum(
      AlbumRecord(
        id: id,
        encryptedName: await _keys.encryptText(_session.masterKey, name, _albumContext(id)),
        createdAt: now.millisecondsSinceEpoch,
      ),
    );
    return Album(id: id, name: name, createdAt: now);
  }

  @override
  Future<void> renameAlbum(String albumId, String name) async =>
      _db.renameAlbum(albumId, await _keys.encryptText(_session.masterKey, name, _albumContext(albumId)));

  @override
  Future<void> deleteAlbum(String albumId) => _db.deleteAlbum(albumId);

  @override
  Future<void> releaseSecrets() async {
    _recovered = false;
    _thumbCache.clear();
    await _server.stop();
    await _paths.clearTemp();
  }

  Future<Uint8List> _decryptOriginal(MediaItem item) => _withFileKey(
    item.id,
    (key) => _cipher.decryptToMemory(source: _paths.mediaFile(item.id), key: key, fileId: item.id),
  );

  Future<T> _withFileKey<T>(String id, Future<T> Function(Uint8List key) action) async {
    final record = await _db.media(id);
    if (record == null) throw const StorageFailure('Item not found.');
    final key = await _keys.unwrapFileKey(_session.masterKey, record.wrappedKey, id);
    try {
      return await action(key);
    } finally {
      wipe(key);
    }
  }

  /// Shared items are view-only: only the admin device can change or export them.
  static void _requireOwned(List<MediaItem> items) {
    if (items.any((i) => i.isShared)) throw const StorageFailure('Shared items are view-only.');
  }

  static String nameContext(String id) => 'media-name/$id';
  static String _albumContext(String id) => 'album-name/$id';
  static String thumbId(String id) => '$id/thumb';

  static String _extensionOf(String path, bool isVideo) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (ext.isNotEmpty && ext.length <= 5) return ext;
    return isVideo ? 'mp4' : 'jpg';
  }

  static Future<void> _deleteQuietly(List<File> files) async {
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Recovery will retry.
      }
    }
  }
}
