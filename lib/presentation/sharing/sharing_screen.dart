import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/failures.dart';
import '../../core/theme/app_theme.dart';
import '../../data/sharing/sharing_client.dart';
import '../../data/sharing/sharing_protocol.dart';
import '../../injection.dart';
import '../vault/vault_providers.dart';

class SharingScreen extends ConsumerWidget {
  const SharingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sharing')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            _AdminSection(),
            SizedBox(height: 16),
            _ViewerSection(),
            SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Sharing works over your local Wi-Fi only — nothing is uploaded. The admin phone shares '
                'while its vault is open; viewers sync when both phones are on the same network. '
                'Viewers can look at shared items but cannot save, move or delete them.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminSection extends ConsumerStatefulWidget {
  const _AdminSection();

  @override
  ConsumerState<_AdminSection> createState() => _AdminSectionState();
}

class _AdminSectionState extends ConsumerState<_AdminSection> {
  @override
  void dispose() {
    final host = ref.read(sharingHostProvider);
    if (host.pairingOpen) unawaited(host.closePairing());
    super.dispose();
  }

  Future<void> _openPairing() async {
    try {
      await ref.read(sharingHostProvider).openPairing();
    } on Object {
      if (mounted) _toast(context, 'Could not start sharing on this network.');
    }
  }

  Future<void> _remove(PairedDevice viewer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${viewer.name}?'),
        content: const Text(
          'Items already shared are deleted from that device the next time it syncs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true)
      await ref.read(sharingHostProvider).removeViewer(viewer.id);
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(sharingHostProvider);
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) {
        final pending = host.pending;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionTitle(
                  icon: Icons.admin_panel_settings_rounded,
                  title: 'Share this vault (admin)',
                ),
                const SizedBox(height: 4),
                const Text(
                  'Devices you add see your photos and videos, view-only.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                for (final viewer in host.viewers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.phone_iphone_rounded),
                    title: Text(viewer.name),
                    subtitle: Text(
                      host.isRunning ? 'Can view · sharing now' : 'Can view',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove access',
                      icon: const Icon(
                        Icons.person_remove_rounded,
                        color: AppColors.danger,
                      ),
                      onPressed: () => _remove(viewer),
                    ),
                  ),
                const SizedBox(height: 12),
                if (pending != null)
                  _CodeBox(
                    title: '${pending.device.name} wants to view',
                    code: pending.code,
                    hint: 'Allow only if the other phone shows the same code.',
                    actions: [
                      TextButton(
                        onPressed: host.deny,
                        child: const Text('Deny'),
                      ),
                      FilledButton(
                        onPressed: host.approve,
                        child: const Text('Allow'),
                      ),
                    ],
                  )
                else if (host.pairingOpen)
                  Column(
                    children: [
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text(
                        'Waiting for a viewer… On the other phone open Private → Shared → Connect to admin.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: host.closePairing,
                        child: const Text('Stop'),
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _openPairing,
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('Add a viewer device'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _ViewerStep { idle, searching, confirming, waiting }

class _ViewerSection extends ConsumerStatefulWidget {
  const _ViewerSection();

  @override
  ConsumerState<_ViewerSection> createState() => _ViewerSectionState();
}

class _ViewerSectionState extends ConsumerState<_ViewerSection> {
  _ViewerStep _step = _ViewerStep.idle;
  PairedDevice? _admin;
  final _found = <DiscoveredAdmin>[];
  StreamSubscription<DiscoveredAdmin>? _search;
  PairingAttempt? _attempt;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAdmin());
  }

  @override
  void dispose() {
    unawaited(_search?.cancel());
    super.dispose();
  }

  Future<void> _loadAdmin() async {
    final admin = await ref.read(sharingClientProvider).linkedAdmin();
    if (mounted) setState(() => _admin = admin);
  }

  void _searchAdmins() {
    setState(() {
      _step = _ViewerStep.searching;
      _found.clear();
    });
    _search = ref
        .read(sharingClientProvider)
        .discover(timeout: const Duration(seconds: 20))
        .listen(
          (admin) => setState(() => _found.add(admin)),
          onError: (_) => _fail('Could not search the local network.'),
          onDone: () {
            if (mounted && _step == _ViewerStep.searching && _found.isEmpty) {
              _fail(
                'No admin device found. On the admin phone tap "Add a viewer device".',
              );
            }
          },
        );
  }

  Future<void> _pair(DiscoveredAdmin admin) async {
    await _search?.cancel();
    try {
      final attempt = await ref
          .read(sharingClientProvider)
          .requestPairing(admin);
      setState(() {
        _attempt = attempt;
        _step = _ViewerStep.confirming;
      });
    } on VaultFailure catch (e) {
      _fail(e.message);
    }
  }

  Future<void> _confirm() async {
    final attempt = _attempt;
    if (attempt == null) return;
    setState(() => _step = _ViewerStep.waiting);
    try {
      final approved = await ref
          .read(sharingClientProvider)
          .waitForApproval(attempt);
      if (!mounted) return;
      if (!approved) return _fail('The admin device did not allow this phone.');
      setState(() {
        _admin = attempt.admin;
        _step = _ViewerStep.idle;
      });
      _toast(
        context,
        'Linked to ${attempt.admin.name}. Shared items appear in the Shared tab.',
      );
      unawaited(_syncNow());
    } on VaultFailure catch (e) {
      _fail(e.message);
    }
  }

  Future<void> _syncNow() async {
    try {
      await ref.read(sharingClientProvider).sync();
      await ref.read(vaultLibraryProvider.notifier).reload();
    } on VaultFailure {
      // The Shared tab shows sync status and retries.
    }
  }

  Future<void> _unlink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlink admin device?'),
        content: const Text(
          'Everything received from it is deleted from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(sharingClientProvider).unlink();
    await ref.read(vaultLibraryProvider.notifier).reload();
    if (mounted) setState(() => _admin = null);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _step = _ViewerStep.idle;
      _attempt = null;
    });
    _toast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final admin = _admin;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              icon: Icons.visibility_rounded,
              title: 'View an admin\'s vault',
            ),
            const SizedBox(height: 4),
            const Text(
              'Receive another phone\'s photos and videos here, view-only.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (admin != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_rounded),
                title: Text(admin.name),
                subtitle: const Text('Linked admin'),
                trailing: TextButton(
                  onPressed: _unlink,
                  child: const Text('Unlink'),
                ),
              )
            else
              switch (_step) {
                _ViewerStep.idle => OutlinedButton.icon(
                  onPressed: _searchAdmins,
                  icon: const Icon(Icons.wifi_find_rounded),
                  label: const Text('Connect to admin device'),
                ),
                _ViewerStep.searching => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text(
                      'Searching this Wi-Fi…',
                      textAlign: TextAlign.center,
                    ),
                    for (final found in _found)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.phone_iphone_rounded),
                        title: Text(found.name),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _pair(found),
                      ),
                  ],
                ),
                _ViewerStep.confirming => _CodeBox(
                  title: 'Pairing with ${_attempt!.admin.name}',
                  code: _attempt!.code,
                  hint: 'Check the admin phone shows this exact code.',
                  actions: [
                    TextButton(
                      onPressed: () => _fail('Pairing cancelled.'),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: _confirm,
                      child: const Text('Codes match'),
                    ),
                  ],
                ),
                _ViewerStep.waiting => _CodeBox(
                  title: 'Waiting for the admin to allow…',
                  code: _attempt!.code,
                  hint: 'Tap "Allow" on the admin phone.',
                  actions: const [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ],
                ),
              },
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.title,
    required this.code,
    required this.hint,
    required this.actions,
  });

  final String title;
  final String code;
  final String hint;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            '${code.substring(0, 3)} ${code.substring(3)}',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 8,
            children: actions,
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
