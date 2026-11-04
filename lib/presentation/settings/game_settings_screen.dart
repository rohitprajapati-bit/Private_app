import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../common/palette_keypad.dart';
import '../game/game_providers.dart';

class GameSettingsScreen extends ConsumerWidget {
  const GameSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(gameSettingsProvider);
    final progress = ref.watch(gameProgressProvider);
    final notifier = ref.read(gameSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Sound effects'),
                    secondary: const Icon(Icons.volume_up_rounded),
                    value: settings.sound,
                    onChanged: (v) => notifier.update(settings.copyWith(sound: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Vibration'),
                    secondary: const Icon(Icons.vibration_rounded),
                    value: settings.haptics,
                    onChanged: (v) => notifier.update(settings.copyWith(haptics: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Theme colour'),
                    const SizedBox(height: 12),
                    PaletteKeypad(
                      selected: settings.paletteIndex,
                      onTap: (i) => notifier.update(settings.copyWith(paletteIndex: i)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.emoji_events_rounded),
                    title: const Text('Statistics'),
                    subtitle: Text(
                      'Best ${progress.bestScore} · Level ${progress.highestLevel} · '
                      '${progress.totalMatches} matches · ${progress.gamesPlayed} games',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restart_alt_rounded, color: AppColors.danger),
                    title: const Text('Reset progress'),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Reset progress?'),
                          content: const Text('Your levels and best score will be cleared.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
                          ],
                        ),
                      );
                      if (ok == true) ref.read(gameProgressProvider.notifier).reset();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text('${AppConstants.appName} · 1.0', style: TextStyle(color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
