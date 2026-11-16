import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../core/theme/app_theme.dart';
import '../../data/sharing/sharing_client.dart';
import '../../data/sharing/sharing_protocol.dart';
import '../../injection.dart';
import '../../routes/app_router.dart';
import '../gallery/media_grid.dart';
import '../vault/vault_providers.dart';

/// Items received from the linked admin device, view-only. Syncs on open and every
/// [_interval] while the vault is open.
class SharedTab extends ConsumerStatefulWidget {
  const SharedTab({super.key});

  @override
  ConsumerState<SharedTab> createState() => _SharedTabState();
}

class _SharedTabState extends ConsumerState<SharedTab> {
  static const _interval = Duration(seconds: 30);

  PairedDevice? _admin;
  bool _loaded = false;
  String? _status;
  Timer? _timer;
  // Read once: `ref` must not be used in dispose().
  late final SharingClient _client;

  @override
  void initState() {
    super.initState();
    _client = ref.read(sharingClientProvider);
    _client.addListener(_onClientChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client.removeListener(_onClientChanged);
    super.dispose();
  }

  /// Linking or unlinking on the Sharing screen.
  void _onClientChanged() => unawaited(_load());

  Future<void> _load() async {
    final admin = await ref.read(sharingClientProvider).linkedAdmin().catchError((_) => null);
    if (!mounted) return;
    final changed = admin?.id != _admin?.id || !_loaded;
    setState(() {
      _admin = admin;
      _loaded = true;
    });
    if (!changed) return;
    _timer?.cancel();
    if (admin != null) {
      _timer = Timer.periodic(_interval, (_) => unawaited(_sync()));
      unawaited(_sync());
    }
  }

  Future<void> _sync() async {
    final client = _client;
    if (client.syncing || !ref.read(sessionProvider).isUnlocked) return;
    // Read before any await: the tab may be gone when the sync finishes.
    final library = ref.read(vaultLibraryProvider.notifier);
    try {
      // The first listing after unlock runs recovery, which deletes in-flight downloads.
      await ref.read(vaultLibraryProvider.future);
      final result = await client.sync();
      if (result.added > 0 || result.removed > 0) await library.reload();
      _setStatus(
        result.failed > 0 ? '${result.failed} item(s) could not be received.' : 'Up to date',
      );
    } on VaultLocked {
      // The vault closed mid-sync; the router has already left this screen.
    } on VaultFailure catch (e) {
      _setStatus(e.message);
      // Access removed: the client already unlinked and deleted everything.
      await library.reload();
    }
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final admin = _admin;
    if (admin == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.devices_rounded, size: 56, color: AppColors.textMuted),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: ref.read(sharingHostProvider),
                builder: (context, _) {
                  final viewers = ref.read(sharingHostProvider).viewers;
                  return Text(
                    viewers.isEmpty
                        ? 'Share this vault with another phone, or view one shared with you.'
                        : 'Sharing with ${viewers.map((v) => v.name).join(', ')} while this vault is open.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted),
                  );
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go(Routes.sharing),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Set up sharing'),
              ),
              if (AppConstants.brokerBaseUrl.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context.push(Routes.online),
                  icon: const Icon(Icons.vpn_key_rounded),
                  label: const Text('Enter an access code'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final syncing = ref.watch(sharingClientProvider).syncing;
    return Column(
      children: [
        Material(
          color: AppColors.surface,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.visibility_rounded),
            title: Text('From ${admin.name} · view only'),
            subtitle: Text(syncing ? 'Syncing…' : _status ?? 'Waiting to sync'),
            trailing: syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(tooltip: 'Sync now', icon: const Icon(Icons.sync_rounded), onPressed: _sync),
          ),
        ),
        const Expanded(child: MediaGrid(shared: true, basePath: Routes.vault)),
      ],
    );
  }
}
