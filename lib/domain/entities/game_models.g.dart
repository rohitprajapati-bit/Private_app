// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'game_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_GameSettings _$GameSettingsFromJson(Map<String, dynamic> json) =>
    _GameSettings(
      sound: json['sound'] as bool? ?? true,
      haptics: json['haptics'] as bool? ?? true,
      paletteIndex: (json['paletteIndex'] as num?)?.toInt() ?? 3,
    );

Map<String, dynamic> _$GameSettingsToJson(_GameSettings instance) =>
    <String, dynamic>{
      'sound': instance.sound,
      'haptics': instance.haptics,
      'paletteIndex': instance.paletteIndex,
    };

_GameProgress _$GameProgressFromJson(Map<String, dynamic> json) =>
    _GameProgress(
      highestLevel: (json['highestLevel'] as num?)?.toInt() ?? 1,
      bestScore: (json['bestScore'] as num?)?.toInt() ?? 0,
      totalMatches: (json['totalMatches'] as num?)?.toInt() ?? 0,
      gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$GameProgressToJson(_GameProgress instance) =>
    <String, dynamic>{
      'highestLevel': instance.highestLevel,
      'bestScore': instance.bestScore,
      'totalMatches': instance.totalMatches,
      'gamesPlayed': instance.gamesPlayed,
    };
