import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/game_models.dart';

enum GameSound { tap, match, wrong, level, gameOver }

/// Sound effects and haptics, respecting the player's settings.
class GameFeedback {
  GameFeedback() {
    // Mix with the user's music instead of stopping it, and honour the silent switch on iOS.
    // The generic AudioContextConfig rejects that combination on iOS, but the `ambient`
    // category provides exactly that behaviour.
    AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
      ),
    );
  }

  final _players = <GameSound, AudioPlayer>{};

  static const _files = {
    GameSound.tap: 'sounds/tap.wav',
    GameSound.match: 'sounds/match.wav',
    GameSound.wrong: 'sounds/wrong.wav',
    GameSound.level: 'sounds/level.wav',
    GameSound.gameOver: 'sounds/gameover.wav',
  };

  Future<void> play(GameSound sound, GameSettings settings) async {
    if (settings.haptics) {
      switch (sound) {
        case GameSound.tap:
          await HapticFeedback.selectionClick();
        case GameSound.match:
          await HapticFeedback.lightImpact();
        case GameSound.wrong || GameSound.gameOver:
          await HapticFeedback.heavyImpact();
        case GameSound.level:
          await HapticFeedback.mediumImpact();
      }
    }
    if (!settings.sound) return;
    try {
      final player = _players[sound] ??= AudioPlayer();
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.stop();
      await player.play(AssetSource(_files[sound]!));
    } on Object {
      // Audio is cosmetic; never let it break the game.
    }
  }

  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
  }
}
