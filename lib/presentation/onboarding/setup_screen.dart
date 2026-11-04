import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failures.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/usecases/password_policy.dart';
import '../../injection.dart';
import '../../platform/platform_services.dart';
import '../common/password_field.dart';
import '../common/sequence_recorder.dart';

enum _Step { intro, password, sequence, creating, biometrics }

/// First launch: password, hidden-entry sequence, optional biometrics.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  _Step _step = _Step.intro;
  bool _acknowledged = false;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  BiometricStatus _biometrics = BiometricStatus.none;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submitPassword() {
    final error = validateNewPassword(_password.text, _confirm.text);
    setState(() {
      _error = error;
      if (error == null) _step = _Step.sequence;
    });
  }

  Future<void> _create(List<int> sequence) async {
    setState(() => _step = _Step.creating);
    final auth = ref.read(authRepositoryProvider);
    try {
      await auth.setup(password: _password.text, secretSequence: sequence);
      _password.clear();
      _confirm.clear();
      final status = await auth.biometricStatus();
      if (!mounted) return;
      if (status.available) {
        setState(() {
          _biometrics = status;
          _step = _Step.biometrics;
        });
      } else {
        _finish();
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Setup failed. Please try again.';
        _step = _Step.password;
      });
    }
  }

  Future<void> _enableBiometrics() async {
    try {
      await ref.read(authRepositoryProvider).setBiometricEnabled(true);
      _finish();
    } on VaultFailure catch (e) {
      setState(() => _error = e.message);
    }
  }

  /// Lock and hand over to the game; the router leaves /setup once configured.
  void _finish() {
    final session = ref.read(sessionProvider);
    session.lock();
    session.markConfigured();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _buildStep()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
    _Step.intro => _intro(),
    _Step.password => _passwordStep(),
    _Step.sequence => _Card(
      key: const ValueKey('sequence'),
      icon: Icons.palette_rounded,
      title: 'Choose your secret colours',
      body:
          'To open your private space later: start a game, tap pause, then tap these colours '
          'in order on “Tile style”. Nothing else in the app reveals it.',
      child: SequenceRecorder(onConfirmed: _create),
    ),
    _Step.creating => const _Card(
      key: ValueKey('creating'),
      icon: Icons.lock_rounded,
      title: 'Securing…',
      body: 'Generating keys. This takes a few seconds.',
      child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
    ),
    _Step.biometrics => _Card(
      key: const ValueKey('biometrics'),
      icon: Icons.fingerprint_rounded,
      title: 'Use ${_biometrics.label}?',
      body: 'Unlock with ${_biometrics.label} instead of typing your password. Your password always works too.',
      child: Column(
        children: [
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _enableBiometrics, child: Text('Enable ${_biometrics.label}')),
          ),
          TextButton(onPressed: _finish, child: const Text('Not now')),
        ],
      ),
    ),
  };

  Widget _intro() => _Card(
    key: const ValueKey('intro'),
    icon: Icons.shield_rounded,
    title: 'Set up your private space',
    body:
        'Photos and videos you add are encrypted on this device with AES-256. Nothing is uploaded. '
        'Your password is the only key.',
    child: Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _acknowledged,
          onChanged: (v) => setState(() => _acknowledged = v ?? false),
          title: const Text(
            'I understand a forgotten password cannot be recovered, and uninstalling the app deletes everything inside.',
            style: TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _acknowledged ? () => setState(() => _step = _Step.password) : null,
            child: const Text('Continue'),
          ),
        ),
      ],
    ),
  );

  Widget _passwordStep() => _Card(
    key: const ValueKey('password'),
    icon: Icons.password_rounded,
    title: 'Create a password',
    body: 'At least 8 characters. A longer passphrase is stronger.',
    child: Column(
      children: [
        PasswordField(controller: _password, label: 'Password', autofocus: true),
        const SizedBox(height: 8),
        PasswordStrengthBar(password: _password.text),
        const SizedBox(height: 12),
        PasswordField(
          controller: _confirm,
          label: 'Confirm password',
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitPassword(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _submitPassword, child: const Text('Next'))),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.icon, required this.title, required this.body, required this.child});

  final IconData icon;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
