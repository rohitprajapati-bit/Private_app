import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/usecases/generate_round.dart';
import 'game_feedback.dart';
import 'game_providers.dart';

part 'game_controller.freezed.dart';

enum GameStatus { ready, playing, paused, levelComplete, gameOver }

@freezed
abstract class GameState with _$GameState {
  const factory GameState({
    @Default(1) int level,
    ColorRound? round,
    @Default(0) int roundInLevel,
    @Default(0) int score,
    @Default(0) int streak,
    @Default(Duration.zero) Duration timeLeft,
    @Default(Duration(seconds: 1)) Duration levelTime,
    @Default(GameStatus.ready) GameStatus status,

    /// Incremented on each wrong tap so the grid can replay its shake animation.
    @Default(0) int mistakes,
    int? wrongIndex,
  }) = _GameState;
}

final gameControllerProvider =
    NotifierProvider.autoDispose<GameController, GameState>(GameController.new);

class GameController extends Notifier<GameState> {
  static const _tick = Duration(milliseconds: 100);
  static const _wrongPenalty = Duration(seconds: 2);

  final _generator = RoundGenerator();
  Timer? _timer;

  @override
  GameState build() {
    ref.onDispose(() => _timer?.cancel());
    return const GameState();
  }

  void start(int level) {
    final time = RoundGenerator.timeFor(level);
    state = GameState(
      level: level,
      round: _generator.next(level),
      timeLeft: time,
      levelTime: time,
      status: GameStatus.playing,
      score: state.status == GameStatus.levelComplete ? state.score : 0,
      streak: state.status == GameStatus.levelComplete ? state.streak : 0,
    );
    _startTimer();
  }

  void restart() => start(state.level);

  void nextLevel() => start(state.level + 1);

  void pause() {
    if (state.status != GameStatus.playing) return;
    _timer?.cancel();
    state = state.copyWith(status: GameStatus.paused);
  }

  void resume() {
    if (state.status != GameStatus.paused) return;
    state = state.copyWith(status: GameStatus.playing);
    _startTimer();
  }

  void tap(int index) {
    final round = state.round;
    if (state.status != GameStatus.playing || round == null) return;
    final settings = ref.read(gameSettingsProvider);
    final feedback = ref.read(gameFeedbackProvider);

    if (index != round.answerIndex) {
      final left = state.timeLeft - _wrongPenalty;
      state = state.copyWith(
        streak: 0,
        mistakes: state.mistakes + 1,
        wrongIndex: index,
        timeLeft: left.isNegative ? Duration.zero : left,
      );
      unawaited(feedback.play(GameSound.wrong, settings));
      if (state.timeLeft == Duration.zero) _gameOver();
      return;
    }

    final streak = state.streak + 1;
    final score = state.score + RoundGenerator.pointsFor(state.level, streak);
    final roundInLevel = state.roundInLevel + 1;
    ref
        .read(gameProgressProvider.notifier)
        .update((p) => p.copyWith(totalMatches: p.totalMatches + 1));

    if (roundInLevel >= RoundGenerator.roundsPerLevel) {
      _timer?.cancel();
      // Remaining time becomes bonus points.
      final bonus = state.timeLeft.inSeconds * state.level;
      state = state.copyWith(
        score: score + bonus,
        streak: streak,
        roundInLevel: roundInLevel,
        status: GameStatus.levelComplete,
        wrongIndex: null,
      );
      final reached = state.level + 1;
      ref
          .read(gameProgressProvider.notifier)
          .update(
            (p) => p.copyWith(
              highestLevel: max(p.highestLevel, reached),
              bestScore: max(p.bestScore, state.score),
            ),
          );
      unawaited(feedback.play(GameSound.level, settings));
      return;
    }

    state = state.copyWith(
      score: score,
      streak: streak,
      roundInLevel: roundInLevel,
      round: _generator.next(state.level),
      wrongIndex: null,
    );
    unawaited(feedback.play(GameSound.match, settings));
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      if (state.status != GameStatus.playing) return;
      final left = state.timeLeft - _tick;
      if (left <= Duration.zero) {
        state = state.copyWith(timeLeft: Duration.zero);
        _gameOver();
      } else {
        state = state.copyWith(timeLeft: left);
      }
    });
  }

  void _gameOver() {
    _timer?.cancel();
    state = state.copyWith(status: GameStatus.gameOver);
    ref
        .read(gameProgressProvider.notifier)
        .update(
          (p) => p.copyWith(
            bestScore: max(p.bestScore, state.score),
            gamesPlayed: p.gamesPlayed + 1,
          ),
        );
    unawaited(
      ref
          .read(gameFeedbackProvider)
          .play(GameSound.gameOver, ref.read(gameSettingsProvider)),
    );
  }
}
