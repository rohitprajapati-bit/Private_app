import '../entities/game_models.dart';

abstract interface class GameRepository {
  GameSettings loadSettings();
  Future<void> saveSettings(GameSettings settings);

  GameProgress loadProgress();
  Future<void> saveProgress(GameProgress progress);
}
