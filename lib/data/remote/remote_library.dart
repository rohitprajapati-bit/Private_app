/// Plain models for an online (code-based) view-only library, as the broker returns it.
/// These never touch the encrypted local vault; they only describe what to stream.
class RemoteItem {
  const RemoteItem({
    required this.id,
    required this.isVideo,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.hasThumb,
    this.width,
    this.height,
    this.durationMs,
  });

  final String id;
  final bool isVideo;
  final String name;
  final String extension;
  final int sizeBytes;
  final bool hasThumb;
  final int? width;
  final int? height;
  final int? durationMs;

  factory RemoteItem.fromJson(Map<String, dynamic> j) => RemoteItem(
    id: j['id'] as String,
    isVideo: j['type'] == 'video',
    name: (j['name'] as String?) ?? '',
    extension: (j['ext'] as String?) ?? '',
    sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
    hasThumb: j['hasThumb'] == true,
    width: (j['width'] as num?)?.toInt(),
    height: (j['height'] as num?)?.toInt(),
    durationMs: (j['durationMs'] as num?)?.toInt(),
  );
}

class RemoteLibrary {
  const RemoteLibrary({required this.id, required this.name, required this.items});

  final String id;
  final String name;
  final List<RemoteItem> items;

  RemoteItem? itemById(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  factory RemoteLibrary.fromJson(Map<String, dynamic> j) => RemoteLibrary(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    items: [
      for (final e in (j['items'] as List?) ?? const [])
        RemoteItem.fromJson(e as Map<String, dynamic>),
    ],
  );
}
