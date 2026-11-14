import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/secret_sequence.dart';
import '../../domain/entities/game_models.dart';
import '../../injection.dart';
import 'game_feedback.dart';

final gameSettingsProvider = NotifierProvider<GameSettingsNotifier, GameSettings>(GameSettingsNotifier.new);

class GameSettingsNotifier extends Notifier<GameSettings> {
  @override
  GameSettings build() => ref.watch(gameRepositoryProvider).loadSettings();

  void update(GameSettings settings) {
    state = settings;
    ref.read(gameRepositoryProvider).saveSettings(settings);
  }
}

final gameProgressProvider = NotifierProvider<GameProgressNotifier, GameProgress>(GameProgressNotifier.new);

class GameProgressNotifier extends Notifier<GameProgress> {
  @override
  GameProgress build() => ref.watch(gameRepositoryProvider).loadProgress();

  void update(GameProgress Function(GameProgress) change) {
    state = change(state);
    ref.read(gameRepositoryProvider).saveProgress(state);
  }

  void reset() => update((_) => const GameProgress());
}

final gameFeedbackProvider = Provider((ref) {
  final feedback = GameFeedback();
  ref.onDispose(feedback.dispose);
  return feedback;
});

/// Loaded once per game screen; drives the hidden entry in the pause menu.
final secretSequenceMatcherProvider = FutureProvider.autoDispose<SecretSequenceMatcher>(
  (ref) async => SecretSequenceMatcher(await ref.watch(authRepositoryProvider).secretSequence()),
);
