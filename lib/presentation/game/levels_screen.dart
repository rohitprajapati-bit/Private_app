import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/usecases/generate_round.dart';
import '../../routes/app_router.dart';
import 'game_providers.dart';

class LevelsScreen extends ConsumerWidget {
  const LevelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highest = ref.watch(
      gameProgressProvider.select((p) => p.highestLevel),
    );
    final shown = max(30, (highest ~/ 10 + 2) * 10);
    return Scaffold(
      appBar: AppBar(title: const Text('Levels')),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 88,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: shown,
          itemBuilder: (context, index) {
            final level = index + 1;
            final unlocked = level <= highest;
            final grid = RoundGenerator.gridSizeFor(level);
            return Material(
              color: unlocked
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.18)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: unlocked
                    ? () => context.pushReplacement(Routes.play(level))
                    : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    unlocked
                        ? Text(
                            '$level',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : const Icon(
                            Icons.lock_rounded,
                            color: AppColors.textMuted,
                          ),
                    const SizedBox(height: 2),
                    Text(
                      '$grid×$grid',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
