import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/usecases/generate_round.dart';
import '../../injection.dart';
import '../../routes/app_router.dart';
import '../common/palette_keypad.dart';
import 'game_controller.dart';
import 'game_feedback.dart';
import 'game_providers.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.startLevel});

  final int startLevel;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameControllerProvider.notifier).start(widget.startLevel);
    });
    // Pause automatically when the app leaves the foreground.
    _lifecycle = AppLifecycleListener(onInactive: () => ref.read(gameControllerProvider.notifier).pause());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);
    // Keep the matcher loaded while this screen is visible.
    ref.watch(secretSequenceMatcherProvider);

    return PopScope(
      canPop: state.status != GameStatus.playing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.pause();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _Hud(state: state, onPause: controller.pause),
                  Expanded(child: _Board(state: state, onTap: controller.tap)),
                ],
              ),
              if (state.status == GameStatus.paused) _PauseOverlay(onResume: controller.resume, onRestart: controller.restart),
              if (state.status == GameStatus.levelComplete)
                _ResultOverlay(
                  title: 'Level ${state.level} complete!',
                  subtitle: 'Score ${state.score}',
                  primaryLabel: 'Next level',
                  onPrimary: controller.nextLevel,
                ),
              if (state.status == GameStatus.gameOver)
                _ResultOverlay(
                  title: "Time's up",
                  subtitle: 'Score ${state.score} · Best ${ref.watch(gameProgressProvider).bestScore}',
                  primaryLabel: 'Try again',
                  onPrimary: controller.restart,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.state, required this.onPause});

  final GameState state;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final fraction = state.levelTime.inMilliseconds == 0
        ? 0.0
        : (state.timeLeft.inMilliseconds / state.levelTime.inMilliseconds).clamp(0.0, 1.0);
    final low = state.timeLeft < const Duration(seconds: 5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Column(
        children: [
          Row(
            children: [
              Text('Level ${state.level}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              const Icon(Icons.star_rounded, color: Colors.amber),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: Text(
                  '${state.score}',
                  key: ValueKey(state.score),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Pause',
                onPressed: state.status == GameStatus.playing ? onPause : null,
                icon: const Icon(Icons.pause_circle_filled_rounded, size: 32),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.timer_rounded, size: 18, color: low ? AppColors.danger : AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 10,
                    backgroundColor: AppColors.surface,
                    color: low ? AppColors.danger : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text('${state.timeLeft.inSeconds}s', textAlign: TextAlign.end),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < RoundGenerator.roundsPerLevel; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i < state.roundInLevel ? 22 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: i < state.roundInLevel ? Theme.of(context).colorScheme.primary : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.state, required this.onTap});

  final GameState state;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final round = state.round;
    if (round == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Target swatch takes ~22% of the height; the grid stays square and fits the rest.
        final targetSize = min(constraints.maxHeight * 0.22, 120.0);
        final boardSize = min(constraints.maxWidth - 32, constraints.maxHeight - targetSize - 56);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Match this colour', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: targetSize,
              height: targetSize,
              decoration: BoxDecoration(
                color: round.target,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [BoxShadow(color: round.target.withValues(alpha: 0.5), blurRadius: 24)],
              ),
            ),
            const SizedBox(height: 20),
            _Shake(
              trigger: state.mistakes,
              child: SizedBox(
                width: boardSize,
                height: boardSize,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: round.gridSize,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: round.tiles.length,
                  itemBuilder: (context, i) => _Tile(
                    key: ValueKey('${state.level}-${state.roundInLevel}-$i'),
                    color: round.tiles[i],
                    wrong: state.wrongIndex == i,
                    onTap: () => onTap(i),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({super.key, required this.color, required this.wrong, required this.onTap});

  final Color color;
  final bool wrong;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(scale: _pressed ? 0.9 : scale, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(12),
            border: widget.wrong ? Border.all(color: Colors.white, width: 3) : null,
          ),
          child: widget.wrong ? const Icon(Icons.close_rounded, color: Colors.white) : null,
        ),
      ),
    );
  }
}

/// Horizontal shake each time [trigger] changes.
class _Shake extends StatelessWidget {
  const _Shake({required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: trigger == 0 ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 400),
      builder: (context, t, child) =>
          Transform.translate(offset: Offset(sin(t * pi * 6) * 10 * (1 - t), 0), child: child),
      child: child,
    );
  }
}

/// Pause menu. The "Tile style" palette is a real setting — and the owner's hidden entrance:
/// tapping the secret colour sequence here opens the password screen.
class _PauseOverlay extends ConsumerWidget {
  const _PauseOverlay({required this.onResume, required this.onRestart});

  final VoidCallback onResume;
  final VoidCallback onRestart;

  void _onPaletteTap(BuildContext context, WidgetRef ref, int index) {
    final settings = ref.read(gameSettingsProvider);
    ref.read(gameSettingsProvider.notifier).update(settings.copyWith(paletteIndex: index));
    ref.read(gameFeedbackProvider).play(GameSound.tap, settings);

    final matcher = ref.read(secretSequenceMatcherProvider).value;
    if (matcher != null && matcher.add(index)) {
      ref.read(sessionProvider).grantEntry();
      context.push(Routes.unlock);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paletteIndex = ref.watch(gameSettingsProvider.select((s) => s.paletteIndex));
    return _Dim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Paused', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onResume, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Resume')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: onRestart, icon: const Icon(Icons.replay_rounded), label: const Text('Restart level')),
          const SizedBox(height: 10),
          TextButton.icon(onPressed: () => context.pop(), icon: const Icon(Icons.home_rounded), label: const Text('Quit to menu')),
          const SizedBox(height: 20),
          const Text('Tile style', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          PaletteKeypad(selected: paletteIndex, onTap: (i) => _onPaletteTap(context, ref, i)),
        ],
      ),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({required this.title, required this.subtitle, required this.primaryLabel, required this.onPrimary});

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return _Dim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.elasticOut,
            builder: (context, s, child) => Transform.scale(scale: s, child: child),
            child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
          const SizedBox(height: 24),
          FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
          const SizedBox(height: 10),
          TextButton(onPressed: () => context.pop(), child: const Text('Menu')),
        ],
      ),
    );
  }
}

class _Dim extends StatelessWidget {
  const _Dim({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Card(
                color: AppColors.surfaceHigh,
                child: Padding(padding: const EdgeInsets.all(24), child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
