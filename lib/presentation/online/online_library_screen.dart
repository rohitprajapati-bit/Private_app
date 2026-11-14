import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../core/theme/app_theme.dart';
import '../../data/remote/remote_library.dart';
import '../../injection.dart';
import '../../routes/app_router.dart';

/// The open online library plus the streaming headers, so the viewers can look up an item by id
/// and stream it. Null library means no code is redeemed (or access was removed).
class RemoteSessionState {
  const RemoteSessionState(this.library, this.headers);
  final RemoteLibrary? library;
  final Map<String, String> headers;
}

final remoteSessionProvider =
    NotifierProvider<RemoteSessionNotifier, RemoteSessionState>(RemoteSessionNotifier.new);

class RemoteSessionNotifier extends Notifier<RemoteSessionState> {
  @override
  RemoteSessionState build() => const RemoteSessionState(null, {});

  void set(RemoteLibrary? library, Map<String, String> headers) =>
      state = RemoteSessionState(library, headers);
}

/// Online, code-based, view-only library. The user enters an access code; the matching library
/// opens and streams from the broker. No save, share, move or delete — view only.
class OnlineLibraryScreen extends ConsumerStatefulWidget {
  const OnlineLibraryScreen({super.key});

  @override
  ConsumerState<OnlineLibraryScreen> createState() => _OnlineLibraryScreenState();
}

class _OnlineLibraryScreenState extends ConsumerState<OnlineLibraryScreen> {
  final _codeController = TextEditingController();
  Map<String, String> _headers = const {};
  RemoteLibrary? _library;
  bool _loading = true;
  bool _working = false;
  String? _error;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final client = ref.read(brokerClientProvider);
    if (!client.isConfigured) {
      setState(() => _loading = false);
      return;
    }
    _headers = await client.authHeaders();
    if (await client.hasAccess()) {
      await _loadLibrary();
      _startHeartbeat();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      AppConstants.remoteHeartbeat,
      (_) => unawaited(ref.read(brokerClientProvider).heartbeat()),
    );
  }

  void _publish(RemoteLibrary? library) =>
      ref.read(remoteSessionProvider.notifier).set(library, _headers);

  Future<void> _loadLibrary() async {
    final client = ref.read(brokerClientProvider);
    try {
      final library = await client.currentLibrary();
      if (!mounted) return;
      _publish(library);
      setState(() {
        _library = library;
        _loading = false;
        _error = null;
      });
      unawaited(client.heartbeat());
    } on SharingFailure catch (e) {
      if (!mounted) return;
      _publish(null);
      setState(() {
        _library = null;
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    final client = ref.read(brokerClientProvider);
    try {
      final library = await client.redeem(code);
      _headers = await client.authHeaders();
      if (!mounted) return;
      _publish(library);
      setState(() => _library = library);
      _startHeartbeat();
    } on SharingFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this library?'),
        content: const Text('The library is removed from this phone. You can re-enter the code to get it back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    _heartbeat?.cancel();
    await ref.read(brokerClientProvider).forget();
    if (!mounted) return;
    _publish(null);
    setState(() {
      _library = null;
      _error = null;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    return Scaffold(
      appBar: AppBar(
        title: Text(library?.name.isNotEmpty == true ? library!.name : 'Online library'),
        actions: [
          if (library != null) ...[
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.sync_rounded), onPressed: _loadLibrary),
            IconButton(tooltip: 'Remove library', icon: const Icon(Icons.link_off_rounded), onPressed: _forget),
          ],
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : !ref.read(brokerClientProvider).isConfigured
            ? _message(Icons.cloud_off_rounded, 'Online libraries are not enabled in this build.')
            : library == null
            ? _codeEntry()
            : _grid(library),
      ),
    );
  }

  Widget _message(IconData icon, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    ),
  );

  Widget _codeEntry() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 24),
      const Icon(Icons.vpn_key_rounded, size: 56, color: AppColors.textMuted),
      const SizedBox(height: 16),
      const Text(
        'Enter your access code',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        'The owner gives you a code. It opens one library, view-only.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted),
      ),
      const SizedBox(height: 24),
      TextField(
        controller: _codeController,
        autocorrect: false,
        textCapitalization: TextCapitalization.characters,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 4),
        decoration: const InputDecoration(hintText: 'CODE', border: OutlineInputBorder()),
        onSubmitted: (_) => _redeem(),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _working ? null : _redeem,
        icon: _working
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.lock_open_rounded),
        label: Text(_working ? 'Opening…' : 'Open library'),
      ),
    ],
  );

  Widget _grid(RemoteLibrary library) {
    if (library.items.isEmpty) {
      return _message(Icons.photo_library_outlined, 'This library is empty for now.');
    }
    return Column(
      children: [
        Material(
          color: AppColors.surface,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.visibility_rounded),
            title: Text('${library.items.length} item(s) · view only'),
            subtitle: Text(_error ?? 'You can view these but not save or delete them.'),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: library.items.length,
            itemBuilder: (context, i) => _Thumb(
              item: library.items[i],
              headers: _headers,
              onTap: () => context.push(
                library.items[i].isVideo
                    ? Routes.onlineVideo(library.items[i].id)
                    : Routes.onlinePhoto(library.items[i].id),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.item, required this.headers, required this.onTap});

  final RemoteItem item;
  final Map<String, String> headers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.read(brokerClientProvider);
    // Use the dedicated thumbnail when the owner uploaded one; for photos without a thumb fall
    // back to the full image; videos without a thumb show an icon (no bytes fetched for them).
    final showImage = item.hasThumb || !item.isVideo;
    final uri = client.mediaUri(item.id, thumb: item.hasThumb);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: AppColors.surfaceHigh,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showImage)
              Image.network(
                uri.toString(),
                headers: headers,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const Center(child: Icon(Icons.image_outlined, color: AppColors.textMuted)),
                errorBuilder: (context, _, _) =>
                    const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted)),
              )
            else
              const Center(child: Icon(Icons.videocam_rounded, color: AppColors.textMuted, size: 32)),
            if (item.isVideo)
              const Align(
                alignment: Alignment.center,
                child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 36),
              ),
          ],
        ),
      ),
    );
  }
}
