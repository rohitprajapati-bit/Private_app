import 'package:freezed_annotation/freezed_annotation.dart';

part 'game_models.freezed.dart';
part 'game_models.g.dart';

@freezed
abstract class GameSettings with _$GameSettings {
  const factory GameSettings({
    @Default(true) bool sound,
    @Default(true) bool haptics,
    @Default(3) int paletteIndex,
  }) = _GameSettings;

  factory GameSettings.fromJson(Map<String, dynamic> json) => _$GameSettingsFromJson(json);
}

@freezed
abstract class GameProgress with _$GameProgress {
  const factory GameProgress({
    @Default(1) int highestLevel,
    @Default(0) int bestScore,
    @Default(0) int totalMatches,
    @Default(0) int gamesPlayed,
  }) = _GameProgress;

  factory GameProgress.fromJson(Map<String, dynamic> json) => _$GameProgressFromJson(json);
}
