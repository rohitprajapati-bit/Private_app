import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failures.dart';
import '../../core/security/vault_session.dart';
import '../../core/theme/app_theme.dart';
import '../../injection.dart';
import '../../platform/platform_services.dart';
import '../common/password_field.dart';

/// Password / biometric gate. Only reachable through the secret in-game sequence; on success
/// the router moves to the vault.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  BiometricStatus _biometrics = BiometricStatus.none;
  Duration _lockout = Duration.zero;
  Timer? _lockoutTimer;
  late final VaultSession _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(sessionProvider);
    unawaited(_init());
  }

  Future<void> _init() async {
    final auth = ref.read(authRepositoryProvider);
    final status = await auth.biometricStatus();
    _startLockoutCountdown(await auth.lockoutRemaining());
    if (!mounted) return;
    setState(() => _biometrics = status);
    if (status.enabled) await _unlockWithBiometrics();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _password.dispose();
    // Leaving without unlocking closes the entrance again.
    if (!_session.isUnlocked) _session.revokeEntry();
    super.dispose();
  }

  void _startLockoutCountdown(Duration remaining) {
    _lockoutTimer?.cancel();
    setState(() => _lockout = remaining);
    if (remaining <= Duration.zero) return;
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _lockout -= const Duration(seconds: 1));
      if (_lockout <= Duration.zero) {
        timer.cancel();
        setState(() => _error = null);
      }
    });
  }

  Future<void> _unlockWithPassword() async {
    if (_busy || _password.text.isEmpty || _lockout > Duration.zero) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).unlockWithPassword(_password.text);
      _password.clear();
    } on LockedOut catch (e) {
      _startLockoutCountdown(e.remaining);
      _setError(e.message);
    } on VaultFailure catch (e) {
      _setError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).unlockWithBiometric();
    } on BiometricFailure catch (e) {
      if (e.reason != BiometricError.cancelled) _setError(e.message);
      if (e.reason == BiometricError.invalidated || e.reason == BiometricError.notEnabled) {
        setState(() => _biometrics = BiometricStatus(available: _biometrics.available, enabled: false, label: _biometrics.label));
      }
    } on VaultFailure catch (e) {
      _setError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setError(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final locked = _lockout > Duration.zero;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'Enter password',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 24),
                  PasswordField(
                    controller: _password,
                    label: 'Password',
                    autofocus: !_biometrics.enabled,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _unlockWithPassword(),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null || locked)
                    Text(
                      locked ? 'Too many attempts. Try again in ${_lockout.inSeconds}s.' : _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy || locked ? null : _unlockWithPassword,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Unlock'),
                  ),
                  if (_biometrics.enabled) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(56, 52)),
                      onPressed: _busy ? null : _unlockWithBiometrics,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: Text('Use ${_biometrics.label}'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
