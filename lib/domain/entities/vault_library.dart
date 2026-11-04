import 'package:freezed_annotation/freezed_annotation.dart';

import 'album.dart';
import 'media_item.dart';

part 'vault_library.freezed.dart';

/// Decrypted metadata snapshot of the open vault (names are only ever plaintext in memory).
@freezed
abstract class VaultLibrary with _$VaultLibrary {
  const VaultLibrary._();

  const factory VaultLibrary({@Default([]) List<MediaItem> items, @Default([]) List<Album> albums}) =
      _VaultLibrary;

  List<MediaItem> ofType(MediaType type) => items.where((i) => i.type == type).toList();

  List<MediaItem> inAlbum(String albumId) => items.where((i) => i.albumId == albumId).toList();
}

enum MediaSort { newest, oldest, name, largest, longest }

extension MediaSorting on List<MediaItem> {
  List<MediaItem> sortedBy(MediaSort sort) {
    final copy = List.of(this);
    switch (sort) {
      case MediaSort.newest:
        copy.sort((a, b) => b.importedAt.compareTo(a.importedAt));
      case MediaSort.oldest:
        copy.sort((a, b) => a.importedAt.compareTo(b.importedAt));
      case MediaSort.name:
        copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case MediaSort.largest:
        copy.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      case MediaSort.longest:
        copy.sort((a, b) => (b.duration ?? Duration.zero).compareTo(a.duration ?? Duration.zero));
    }
    return copy;
  }

  List<MediaItem> matching(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ? this : where((i) => i.name.toLowerCase().contains(q)).toList();
  }
}
