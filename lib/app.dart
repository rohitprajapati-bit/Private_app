import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'injection.dart';
import 'presentation/game/game_providers.dart';
import 'routes/app_router.dart';

class ColorMatchApp extends ConsumerStatefulWidget {
  const ColorMatchApp({super.key});

  @override
  ConsumerState<ColorMatchApp> createState() => _ColorMatchAppState();
}

/// Owns the vault's lifecycle rules: lock on background, lock on inactivity, and wipe
/// everything decrypted whenever the vault locks.
class _ColorMatchAppState extends ConsumerState<ColorMatchApp> {
  late final AppLifecycleListener _lifecycle;
  Timer? _idleTimer;
  bool _wasUnlocked = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    session.addLockListener(_onLock);
    session.addListener(_onSessionChanged);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _idleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (session.isIdleExpired && !session.autoLockSuppressed) session.lock();
    });
  }

  @override
  void dispose() {
    final session = ref.read(sessionProvider);
    session.removeLockListener(_onLock);
    session.removeListener(_onSessionChanged);
    _lifecycle.dispose();
    _idleTimer?.cancel();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    final session = ref.read(sessionProvider);
    if ((state == AppLifecycleState.hidden || state == AppLifecycleState.paused) && !session.autoLockSuppressed) {
      session.lock();
    }
  }

  void _onSessionChanged() {
    final unlocked = ref.read(sessionProvider).isUnlocked;
    if (unlocked != _wasUnlocked) {
      _wasUnlocked = unlocked;
      unawaited(ref.read(platformServicesProvider).setSecureScreen(unlocked));
    }
  }

  void _onLock() {
    unawaited(ref.read(mediaRepositoryProvider).releaseSecrets());
    // Decoded vault images live in Flutter's image cache; drop them.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final paletteIndex = ref.watch(gameSettingsProvider.select((s) => s.paletteIndex));
    final accent = AppConstants.palette[paletteIndex % AppConstants.palette.length];
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ref.read(sessionProvider).recordActivity(),
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(accent),
        routerConfig: router,
      ),
    );
  }
}
