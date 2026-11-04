import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/failures.dart';
import '../../core/security/vault_session.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/repositories/media_repository.dart';
import '../../injection.dart';
import 'vault_providers.dart';

/// User-facing flows shared by the gallery grid, albums and viewers.
abstract final class MediaActions {
  static Future<void> import(BuildContext context, WidgetRef ref, MediaType type, {String? albumId}) async {
    final session = ref.read(sessionProvider);
    final picker = ImagePicker();
    // The system picker sends the app to the background on Android; don't lock for that.
    final files = await session.withoutAutoLock(
      () => type == MediaType.photo ? picker.pickMultiImage(requestFullMetadata: false) : picker.pickMultiVideo(),
    );
    if (files.isEmpty || !context.mounted) return;

    final stream = ref.read(mediaRepositoryProvider).import(files.map((f) => f.path).toList(), type, albumId: albumId);
    final result = await showDialog<ImportProgress>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImportDialog(stream: stream, session: session),
    );
    await ref.read(vaultLibraryProvider.notifier).reload();
    if (!context.mounted || result == null) return;
    final imported = result.total - result.failed;
    final failed = result.failed > 0 ? ', ${result.failed} failed' : '';
    _toast(
      context,
      'Imported $imported$failed. The originals are still in your Photos app — delete them there if needed.',
    );
  }

  static Future<void> export(BuildContext context, WidgetRef ref, List<MediaItem> items) async {
    _toast(context, 'Saving ${items.length} item${items.length == 1 ? '' : 's'} to your gallery…');
    try {
      final saved = await ref.read(mediaRepositoryProvider).export(items);
      if (context.mounted) _toast(context, 'Saved $saved of ${items.length} to your gallery.');
    } on VaultFailure catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  static Future<bool> delete(BuildContext context, WidgetRef ref, List<MediaItem> items) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${items.length} item${items.length == 1 ? '' : 's'}?'),
        content: const Text('They will be permanently erased from the vault. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return false;
    await ref.read(vaultLibraryProvider.notifier).delete(items);
    return true;
  }

  static Future<void> moveToAlbum(BuildContext context, WidgetRef ref, List<MediaItem> items) async {
    final albums = ref.read(vaultLibraryProvider).value?.albums ?? const [];
    const newAlbum = '\u0000new';
    const noAlbum = '\u0000none';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Move to album', style: TextStyle(fontWeight: FontWeight.w700))),
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded),
              title: const Text('New album…'),
              onTap: () => Navigator.pop(context, newAlbum),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_rounded),
              title: const Text('No album'),
              onTap: () => Navigator.pop(context, noAlbum),
            ),
            for (final album in albums)
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(album.name),
                onTap: () => Navigator.pop(context, album.id),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    var albumId = choice == noAlbum ? null : choice;
    if (choice == newAlbum) {
      final name = await promptName(context, title: 'New album');
      if (name == null) return;
      albumId = (await ref.read(vaultLibraryProvider.notifier).createAlbum(name)).id;
    }
    await ref.read(vaultLibraryProvider.notifier).move(items, albumId);
  }

  static Future<String?> promptName(BuildContext context, {required String title, String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Album name'),
          onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.pop(context, v.isEmpty ? null : v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.stream, required this.session});

  final Stream<ImportProgress> stream;
  final VaultSession session;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  ImportProgress? _progress;

  @override
  void initState() {
    super.initState();
    widget.stream.listen(
      (p) {
        widget.session.recordActivity();
        if (mounted) setState(() => _progress = p);
      },
      onDone: () {
        if (mounted) Navigator.pop(context, _progress);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Encrypting…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: p?.overall),
            const SizedBox(height: 12),
            Text(p == null ? 'Preparing…' : '${p.completed} of ${p.total}'),
            const SizedBox(height: 8),
            const Text('Keep the app open until this finishes.', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
