import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failures.dart';
import '../../core/security/vault_session.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/repositories/media_repository.dart';
import '../../injection.dart';
import '../../platform/platform_services.dart';
import 'vault_providers.dart';

/// User-facing flows shared by the gallery grid, albums and viewers.
abstract final class MediaActions {
  static Future<void> import(
    BuildContext context,
    WidgetRef ref,
    MediaType type, {
    String? albumId,
  }) async {
    final session = ref.read(sessionProvider);
    final platform = ref.read(platformServicesProvider);
    // The system picker sends the app to the background on Android; don't lock for that.
    final List<PickedMedia> picked;
    try {
      picked = await session.withoutAutoLock(
        () => platform.pickMedia(video: type == MediaType.video),
      );
    } on PlatformException {
      if (context.mounted) _toast(context, 'Could not open the photo picker.');
      return;
    }
    if (picked.isEmpty || !context.mounted) return;

    final stream = ref
        .read(mediaRepositoryProvider)
        .import(
          [for (final m in picked) ImportSource(path: m.path, name: m.name)],
          type,
          albumId: albumId,
        );
    final result = await showDialog<ImportProgress>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImportDialog(stream: stream, session: session),
    );
    await ref.read(vaultLibraryProvider.notifier).reload();
    if (!context.mounted || result == null) return;

    final imported = result.importedPaths.toSet();
    final failed = result.failed > 0 ? ', ${result.failed} failed' : '';
    if (imported.isEmpty) {
      _toast(context, 'Nothing was imported$failed.');
      return;
    }
    if (!await ref.read(secureStoreProvider).readRemoveOriginals()) {
      if (context.mounted)
        _toast(
          context,
          'Imported ${imported.length}$failed. Originals kept in your gallery.',
        );
      return;
    }

    // Only originals that are now safely encrypted in the vault are removed. The OS shows its
    // own confirmation; iOS moves them to "Recently Deleted", which only the owner can empty.
    final deletable = [
      for (final m in picked)
        if (imported.contains(m.path) && m.sourceId != null) m.sourceId!,
    ];
    String message;
    try {
      final deleted = await session.withoutAutoLock(
        () => platform.deleteOriginals(deletable),
      );
      final kept = imported.length - deleted;
      message =
          'Imported ${imported.length}$failed. Removed $deleted from your gallery'
          '${kept > 0 ? ' ($kept could not be removed)' : ''}.';
      if (Platform.isIOS && deleted > 0)
        message += ' Also empty “Recently Deleted” in Photos.';
    } on GalleryDeleteFailure catch (e) {
      message = 'Imported ${imported.length}$failed. ${e.message}';
    }
    if (context.mounted) _toast(context, message);
  }

  static Future<void> export(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> items,
  ) async {
    _toast(
      context,
      'Saving ${items.length} item${items.length == 1 ? '' : 's'} to your gallery…',
    );
    try {
      final saved = await ref.read(mediaRepositoryProvider).export(items);
      if (context.mounted)
        _toast(context, 'Saved $saved of ${items.length} to your gallery.');
    } on VaultFailure catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> items,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete ${items.length} item${items.length == 1 ? '' : 's'}?',
        ),
        content: const Text(
          'They will be permanently erased from the vault. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await ref.read(vaultLibraryProvider.notifier).delete(items);
    return true;
  }

  static Future<void> moveToAlbum(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> items,
  ) async {
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
            const ListTile(
              title: Text(
                'Move to album',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
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
      final album = await ref
          .read(vaultLibraryProvider.notifier)
          .createAlbum(name);
      if (album == null) return; // vault locked meanwhile
      albumId = album.id;
    }
    await ref.read(vaultLibraryProvider.notifier).move(items, albumId);
  }

  static Future<String?> promptName(
    BuildContext context, {
    required String title,
    String initial = '',
  }) => showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(title: title, initial: initial),
  );

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Owns its controller so it is disposed only after the dialog's closing animation has
/// finished; disposing when the result arrives crashes the still-visible text field.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.pop(context, value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(hintText: 'Album name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
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
      onError: (Object _) {
        if (mounted) Navigator.pop(context, _progress);
      },
      cancelOnError: true,
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
            const Text(
              'Keep the app open until this finishes.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
