import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/vault_library.dart';
import '../../injection.dart';
import '../../routes/app_router.dart';
import '../vault/media_actions.dart';
import '../vault/vault_providers.dart';
import 'encrypted_image.dart';

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// Searchable, sortable, multi-select grid of vault items.
/// [type] filters to photos or videos; [albumId] restricts to one album. [shared] shows only
/// items received from an admin device (view-only: no selection) instead of the owner's own.
class MediaGrid extends ConsumerStatefulWidget {
  const MediaGrid({super.key, this.type, this.albumId, this.shared = false, required this.basePath});

  final MediaType? type;
  final String? albumId;
  final bool shared;

  /// Route prefix for opening items (`/vault` or `/vault/album/<id>`).
  final String basePath;

  @override
  ConsumerState<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends ConsumerState<MediaGrid> {
  String _query = '';
  MediaSort _sort = MediaSort.newest;
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  List<MediaItem> _visible(VaultLibrary library) {
    var items = library.items.where((i) => i.isShared == widget.shared).toList();
    if (widget.type != null) items = items.where((i) => i.type == widget.type).toList();
    if (widget.albumId != null) items = items.where((i) => i.albumId == widget.albumId).toList();
    return items.matching(_query).sortedBy(_sort);
  }

  void _open(MediaItem item, List<MediaItem> visible) {
    if (item.isVideo) {
      context.go(Routes.video(widget.basePath, item.id));
    } else {
      final photoIds = [for (final i in visible) if (!i.isVideo) i.id];
      context.go(Routes.photo(widget.basePath, item.id), extra: photoIds);
    }
  }

  void _toggle(MediaItem item) => setState(() {
    if (!_selected.remove(item.id)) _selected.add(item.id);
  });

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(vaultLibraryProvider);
    final repository = ref.watch(mediaRepositoryProvider);
    return library.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Could not open the vault.')),
      data: (library) {
        final visible = _visible(library);
        _selected.removeWhere((id) => !visible.any((i) => i.id == id));
        final selectedItems = visible.where((i) => _selected.contains(i.id)).toList();
        return Column(
          children: [
            if (_selecting)
              _SelectionBar(
                count: _selected.length,
                onClear: () => setState(_selected.clear),
                onSelectAll: () => setState(() => _selected.addAll(visible.map((i) => i.id))),
                onMove: () async {
                  await MediaActions.moveToAlbum(context, ref, selectedItems);
                  setState(_selected.clear);
                },
                onExport: () async {
                  await MediaActions.export(context, ref, selectedItems);
                  setState(_selected.clear);
                },
                onDelete: () async {
                  if (await MediaActions.delete(context, ref, selectedItems)) setState(_selected.clear);
                },
              )
            else
              _SearchBar(
                sort: _sort,
                showDurationSort: widget.type != MediaType.photo,
                onQuery: (q) => setState(() => _query = q),
                onSort: (s) => setState(() => _sort = s),
              ),
            Expanded(
              child: visible.isEmpty
                  ? _Empty(searching: _query.isNotEmpty, type: widget.type, shared: widget.shared)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = (constraints.maxWidth / 120).floor().clamp(3, 6);
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 96),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final item = visible[index];
                            return _GridTile(
                              item: item,
                              thumbnail: EncryptedThumbnail(item: item, repository: repository),
                              selected: _selected.contains(item.id),
                              selecting: _selecting,
                              onTap: () => _selecting ? _toggle(item) : _open(item, visible),
                              onLongPress: widget.shared ? null : () => _toggle(item),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.item,
    required this.thumbnail,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaItem item;
  final Widget thumbnail;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedScale(scale: selected ? 0.88 : 1, duration: const Duration(milliseconds: 150), child: thumbnail),
            if (item.isVideo)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                      Text(
                        item.duration == null ? '' : formatDuration(item.duration!),
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            if (selecting)
              Positioned(
                top: 6,
                left: 6,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? accent : Colors.white70,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.sort, required this.showDurationSort, required this.onQuery, required this.onSort});

  final MediaSort sort;
  final bool showDurationSort;
  final ValueChanged<String> onQuery;
  final ValueChanged<MediaSort> onSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: onQuery,
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          PopupMenuButton<MediaSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_rounded),
            initialValue: sort,
            onSelected: onSort,
            itemBuilder: (context) => [
              const PopupMenuItem(value: MediaSort.newest, child: Text('Newest first')),
              const PopupMenuItem(value: MediaSort.oldest, child: Text('Oldest first')),
              const PopupMenuItem(value: MediaSort.name, child: Text('Name')),
              const PopupMenuItem(value: MediaSort.largest, child: Text('Largest')),
              if (showDurationSort) const PopupMenuItem(value: MediaSort.longest, child: Text('Longest')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onClear,
    required this.onSelectAll,
    required this.onMove,
    required this.onExport,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final VoidCallback onMove;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(tooltip: 'Cancel', onPressed: onClear, icon: const Icon(Icons.close_rounded)),
            Expanded(child: Text('$count selected', style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(tooltip: 'Select all', onPressed: onSelectAll, icon: const Icon(Icons.select_all_rounded)),
            IconButton(tooltip: 'Move to album', onPressed: onMove, icon: const Icon(Icons.drive_file_move_rounded)),
            IconButton(tooltip: 'Save to gallery', onPressed: onExport, icon: const Icon(Icons.download_rounded)),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_rounded, color: AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching, required this.type, required this.shared});

  final bool searching;
  final MediaType? type;
  final bool shared;

  @override
  Widget build(BuildContext context) {
    final what = switch (type) {
      MediaType.photo => 'photos',
      MediaType.video => 'videos',
      null => 'items',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(searching ? Icons.search_off_rounded : Icons.lock_outline_rounded, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              searching
                  ? 'No matches'
                  : shared
                  ? 'Nothing shared yet.'
                  : 'No $what yet. Tap + to add some.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
