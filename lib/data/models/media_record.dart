import 'dart:typed_data';

/// Row in `media`. Name and per-file key are encrypted under the master key; the remaining
/// columns (type, size, dimensions, dates) are needed for listing and are stored in clear.
class MediaRecord {
  const MediaRecord({
    required this.id,
    required this.type,
    required this.encryptedName,
    required this.extension,
    required this.wrappedKey,
    required this.sizeBytes,
    required this.importedAt,
    required this.committed,
    this.albumId,
    this.durationMs,
    this.width,
    this.height,
    this.sharedFrom,
  });

  final String id;
  final int type;
  final Uint8List encryptedName;
  final String extension;
  final Uint8List wrappedKey;
  final int sizeBytes;
  final int importedAt;
  final bool committed;
  final String? albumId;
  final int? durationMs;
  final int? width;
  final int? height;

  /// Id of the admin device this item was received from; null for the owner's own items.
  final String? sharedFrom;

  Map<String, Object?> toRow() => {
    'id': id,
    'type': type,
    'name_enc': encryptedName,
    'ext': extension,
    'wrapped_key': wrappedKey,
    'size': sizeBytes,
    'imported_at': importedAt,
    'committed': committed ? 1 : 0,
    'album_id': albumId,
    'duration_ms': durationMs,
    'width': width,
    'height': height,
    'shared_from': sharedFrom,
  };

  factory MediaRecord.fromRow(Map<String, Object?> row) => MediaRecord(
    id: row['id']! as String,
    type: row['type']! as int,
    encryptedName: row['name_enc']! as Uint8List,
    extension: row['ext']! as String,
    wrappedKey: row['wrapped_key']! as Uint8List,
    sizeBytes: row['size']! as int,
    importedAt: row['imported_at']! as int,
    committed: row['committed'] == 1,
    albumId: row['album_id'] as String?,
    durationMs: row['duration_ms'] as int?,
    width: row['width'] as int?,
    height: row['height'] as int?,
    sharedFrom: row['shared_from'] as String?,
  );
}

class AlbumRecord {
  const AlbumRecord({required this.id, required this.encryptedName, required this.createdAt});

  final String id;
  final Uint8List encryptedName;
  final int createdAt;

  Map<String, Object?> toRow() => {'id': id, 'name_enc': encryptedName, 'created_at': createdAt};

  factory AlbumRecord.fromRow(Map<String, Object?> row) => AlbumRecord(
    id: row['id']! as String,
    encryptedName: row['name_enc']! as Uint8List,
    createdAt: row['created_at']! as int,
  );
}
