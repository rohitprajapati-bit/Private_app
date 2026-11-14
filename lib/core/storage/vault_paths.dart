import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk layout inside the app's private support directory (never user-visible, excluded
/// from backup):
///   vault/media/{id}.bin   encrypted originals
///   vault/thumbs/{id}.bin  encrypted thumbnails
///   vault/tmp/             in-flight `.part` files and short-lived export copies
///   vault/vault.db         SQLite metadata (sensitive fields encrypted)
class VaultPaths {
  VaultPaths(this.root);

  final Directory root;

  static Future<VaultPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    return VaultPaths(Directory(p.join(support.path, 'vault')));
  }

  Directory get media => Directory(p.join(root.path, 'media'));
  Directory get thumbs => Directory(p.join(root.path, 'thumbs'));
  Directory get temp => Directory(p.join(root.path, 'tmp'));
  String get databasePath => p.join(root.path, 'vault.db');
  File get installMarker => File(p.join(root.path, '.installed'));

  File mediaFile(String id) => File(p.join(media.path, '$id.bin'));
  File thumbFile(String id) => File(p.join(thumbs.path, '$id.bin'));
  File partFile(String id, String kind) => File(p.join(temp.path, '$id.$kind.part'));
  File exportFile(String id, String extension) => File(p.join(temp.path, 'export-$id.$extension'));

  Future<void> ensure() async {
    for (final dir in [root, media, thumbs, temp]) {
      await dir.create(recursive: true);
    }
  }

  /// Deletes the whole vault (database, media, thumbnails). Only for data whose key is gone.
  Future<void> wipe() async {
    if (await root.exists()) await root.delete(recursive: true);
  }

  /// Removes in-flight and exported plaintext copies. Called at startup and on every lock.
  Future<void> clearTemp() async {
    if (!await temp.exists()) return;
    await for (final entity in temp.list()) {
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // Best effort; retried next time.
      }
    }
  }

  /// Removes copies the system photo picker left in the app's caches (e.g. after a crash
  /// mid-import). Android: cache/{uuid}/…  iOS: tmp/picked_*.
  static Future<void> sweepPickerLeftovers() async {
    final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
    final dirs = {(await getTemporaryDirectory()).path, Directory.systemTemp.path};
    for (final path in dirs) {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        final isPickerCopy =
            (Platform.isAndroid && entity is Directory && uuid.hasMatch(name)) ||
            (Platform.isIOS && name.startsWith('picked_'));
        if (!isPickerCopy) continue;
        try {
          await entity.delete(recursive: true);
        } on FileSystemException {
          // Best effort.
        }
      }
    }
  }

  /// True for files the picker copied into our sandbox, which we may delete after import.
  static Future<bool> isPickerCopy(String path) async {
    final roots = [(await getTemporaryDirectory()).path, Directory.systemTemp.path];
    final normalized = p.normalize(path);
    return roots.any((root) => p.isWithin(p.normalize(root), normalized));
  }
}
