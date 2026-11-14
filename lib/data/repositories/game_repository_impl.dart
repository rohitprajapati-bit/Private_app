import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/game_models.dart';
import '../../domain/repositories/game_repository.dart';

/// Game data is not sensitive, so plain SharedPreferences is fine.
class GameRepositoryImpl implements GameRepository {
  GameRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;

  static const _settingsKey = 'game.settings';
  static const _progressKey = 'game.progress';

  @override
  GameSettings loadSettings() => _read(_settingsKey, GameSettings.fromJson) ?? const GameSettings();

  @override
  Future<void> saveSettings(GameSettings settings) =>
      _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));

  @override
  GameProgress loadProgress() => _read(_progressKey, GameProgress.fromJson) ?? const GameProgress();

  @override
  Future<void> saveProgress(GameProgress progress) =>
      _prefs.setString(_progressKey, jsonEncode(progress.toJson()));

  T? _read<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }
}
