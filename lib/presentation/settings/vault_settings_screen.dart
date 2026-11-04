import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/usecases/password_policy.dart';
import '../../injection.dart';
import '../../platform/platform_services.dart';
import '../common/password_field.dart';
import '../common/sequence_recorder.dart';
import '../gallery/media_grid.dart';
import '../vault/vault_providers.dart';

class VaultSettingsScreen extends ConsumerStatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  ConsumerState<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends ConsumerState<VaultSettingsScreen> {
  BiometricStatus _biometrics = BiometricStatus.none;
  Duration _autoLock = AppConstants.defaultAutoLock;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = ref.read(authRepositoryProvider);
    final status = await auth.biometricStatus();
    final autoLock = await auth.autoLockDuration();
    if (mounted) {
      setState(() {
        _biometrics = status;
        _autoLock = autoLock;
      });
    }
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _setBiometrics(bool enabled) async {
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).setBiometricEnabled(enabled);
    } on VaultFailure catch (e) {
      if (mounted && !(e is BiometricFailure && e.reason == BiometricError.cancelled)) _toast(e.message);
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => const _ChangePasswordDialog());
    if (changed == true && mounted) _toast('Password changed.');
  }

  Future<void> _changeSequence() async {
    final taps = await showDialog<List<int>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New secret colours'),
        content: SingleChildScrollView(
          child: SequenceRecorder(onConfirmed: (taps) => Navigator.pop(context, taps)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      ),
    );
    if (taps == null) return;
    await ref.read(authRepositoryProvider).changeSecretSequence(taps);
    if (mounted) _toast('Secret colours updated.');
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(vaultLibraryProvider).value;
    final totalBytes = library?.items.fold<int>(0, (sum, i) => sum + i.sizeBytes) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Vault settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Change password'),
                    onTap: _changePassword,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: Text('Unlock with ${_biometrics.label}'),
                    subtitle: _biometrics.available ? null : const Text('Not available on this device'),
                    value: _biometrics.enabled,
                    onChanged: !_biometrics.available || _busy ? null : _setBiometrics,
                  ),
                  ListTile(
                    leading: const Icon(Icons.palette_rounded),
                    title: const Text('Change secret colours'),
                    subtitle: const Text('Pause a game → Tile style'),
                    onTap: _changeSequence,
                  ),
                  ListTile(
                    leading: const Icon(Icons.timer_rounded),
                    title: const Text('Auto-lock when idle'),
                    trailing: DropdownButton<Duration>(
                      value: _autoLock,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final d in AppConstants.autoLockChoices)
                          DropdownMenuItem(
                            value: d,
                            child: Text(d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s'),
                          ),
                      ],
                      onChanged: (d) async {
                        if (d == null) return;
                        await ref.read(authRepositoryProvider).setAutoLockDuration(d);
                        setState(() => _autoLock = d);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.storage_rounded),
                title: const Text('Storage'),
                subtitle: Text('${library?.items.length ?? 0} items · ${formatBytes(totalBytes)} encrypted'),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Everything is encrypted with AES-256-GCM on this device and never uploaded. '
                'The vault locks when the app goes to the background. A forgotten password cannot be '
                'recovered, and uninstalling the app erases the vault.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final error = validateNewPassword(_next.text, _confirm.text);
    if (error != null) return setState(() => _error = error);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(current: _current.text, next: _next.text);
      if (mounted) Navigator.pop(context, true);
    } on VaultFailure catch (e) {
      if (mounted) setState(() => _error = e is WrongPassword ? 'Current password is incorrect.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PasswordField(controller: _current, label: 'Current password', autofocus: true),
            const SizedBox(height: 12),
            PasswordField(controller: _next, label: 'New password'),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirm,
              label: 'Confirm new password',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Change'),
        ),
      ],
    );
  }
}
