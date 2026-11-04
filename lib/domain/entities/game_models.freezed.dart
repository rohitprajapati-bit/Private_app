// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'game_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$GameSettings {

 bool get sound; bool get haptics; int get paletteIndex;
/// Create a copy of GameSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameSettingsCopyWith<GameSettings> get copyWith => _$GameSettingsCopyWithImpl<GameSettings>(this as GameSettings, _$identity);

  /// Serializes this GameSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameSettings&&(identical(other.sound, sound) || other.sound == sound)&&(identical(other.haptics, haptics) || other.haptics == haptics)&&(identical(other.paletteIndex, paletteIndex) || other.paletteIndex == paletteIndex));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sound,haptics,paletteIndex);

@override
String toString() {
  return 'GameSettings(sound: $sound, haptics: $haptics, paletteIndex: $paletteIndex)';
}


}

/// @nodoc
abstract mixin class $GameSettingsCopyWith<$Res>  {
  factory $GameSettingsCopyWith(GameSettings value, $Res Function(GameSettings) _then) = _$GameSettingsCopyWithImpl;
@useResult
$Res call({
 bool sound, bool haptics, int paletteIndex
});




}
/// @nodoc
class _$GameSettingsCopyWithImpl<$Res>
    implements $GameSettingsCopyWith<$Res> {
  _$GameSettingsCopyWithImpl(this._self, this._then);

  final GameSettings _self;
  final $Res Function(GameSettings) _then;

/// Create a copy of GameSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sound = null,Object? haptics = null,Object? paletteIndex = null,}) {
  return _then(_self.copyWith(
sound: null == sound ? _self.sound : sound // ignore: cast_nullable_to_non_nullable
as bool,haptics: null == haptics ? _self.haptics : haptics // ignore: cast_nullable_to_non_nullable
as bool,paletteIndex: null == paletteIndex ? _self.paletteIndex : paletteIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GameSettings].
extension GameSettingsPatterns on GameSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameSettings() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameSettings value)  $default,){
final _that = this;
switch (_that) {
case _GameSettings():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameSettings value)?  $default,){
final _that = this;
switch (_that) {
case _GameSettings() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool sound,  bool haptics,  int paletteIndex)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameSettings() when $default != null:
return $default(_that.sound,_that.haptics,_that.paletteIndex);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool sound,  bool haptics,  int paletteIndex)  $default,) {final _that = this;
switch (_that) {
case _GameSettings():
return $default(_that.sound,_that.haptics,_that.paletteIndex);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool sound,  bool haptics,  int paletteIndex)?  $default,) {final _that = this;
switch (_that) {
case _GameSettings() when $default != null:
return $default(_that.sound,_that.haptics,_that.paletteIndex);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GameSettings implements GameSettings {
  const _GameSettings({this.sound = true, this.haptics = true, this.paletteIndex = 3});
  factory _GameSettings.fromJson(Map<String, dynamic> json) => _$GameSettingsFromJson(json);

@override@JsonKey() final  bool sound;
@override@JsonKey() final  bool haptics;
@override@JsonKey() final  int paletteIndex;

/// Create a copy of GameSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameSettingsCopyWith<_GameSettings> get copyWith => __$GameSettingsCopyWithImpl<_GameSettings>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GameSettingsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameSettings&&(identical(other.sound, sound) || other.sound == sound)&&(identical(other.haptics, haptics) || other.haptics == haptics)&&(identical(other.paletteIndex, paletteIndex) || other.paletteIndex == paletteIndex));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sound,haptics,paletteIndex);

@override
String toString() {
  return 'GameSettings(sound: $sound, haptics: $haptics, paletteIndex: $paletteIndex)';
}


}

/// @nodoc
abstract mixin class _$GameSettingsCopyWith<$Res> implements $GameSettingsCopyWith<$Res> {
  factory _$GameSettingsCopyWith(_GameSettings value, $Res Function(_GameSettings) _then) = __$GameSettingsCopyWithImpl;
@override @useResult
$Res call({
 bool sound, bool haptics, int paletteIndex
});




}
/// @nodoc
class __$GameSettingsCopyWithImpl<$Res>
    implements _$GameSettingsCopyWith<$Res> {
  __$GameSettingsCopyWithImpl(this._self, this._then);

  final _GameSettings _self;
  final $Res Function(_GameSettings) _then;

/// Create a copy of GameSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sound = null,Object? haptics = null,Object? paletteIndex = null,}) {
  return _then(_GameSettings(
sound: null == sound ? _self.sound : sound // ignore: cast_nullable_to_non_nullable
as bool,haptics: null == haptics ? _self.haptics : haptics // ignore: cast_nullable_to_non_nullable
as bool,paletteIndex: null == paletteIndex ? _self.paletteIndex : paletteIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$GameProgress {

 int get highestLevel; int get bestScore; int get totalMatches; int get gamesPlayed;
/// Create a copy of GameProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameProgressCopyWith<GameProgress> get copyWith => _$GameProgressCopyWithImpl<GameProgress>(this as GameProgress, _$identity);

  /// Serializes this GameProgress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameProgress&&(identical(other.highestLevel, highestLevel) || other.highestLevel == highestLevel)&&(identical(other.bestScore, bestScore) || other.bestScore == bestScore)&&(identical(other.totalMatches, totalMatches) || other.totalMatches == totalMatches)&&(identical(other.gamesPlayed, gamesPlayed) || other.gamesPlayed == gamesPlayed));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,highestLevel,bestScore,totalMatches,gamesPlayed);

@override
String toString() {
  return 'GameProgress(highestLevel: $highestLevel, bestScore: $bestScore, totalMatches: $totalMatches, gamesPlayed: $gamesPlayed)';
}


}

/// @nodoc
abstract mixin class $GameProgressCopyWith<$Res>  {
  factory $GameProgressCopyWith(GameProgress value, $Res Function(GameProgress) _then) = _$GameProgressCopyWithImpl;
@useResult
$Res call({
 int highestLevel, int bestScore, int totalMatches, int gamesPlayed
});




}
/// @nodoc
class _$GameProgressCopyWithImpl<$Res>
    implements $GameProgressCopyWith<$Res> {
  _$GameProgressCopyWithImpl(this._self, this._then);

  final GameProgress _self;
  final $Res Function(GameProgress) _then;

/// Create a copy of GameProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? highestLevel = null,Object? bestScore = null,Object? totalMatches = null,Object? gamesPlayed = null,}) {
  return _then(_self.copyWith(
highestLevel: null == highestLevel ? _self.highestLevel : highestLevel // ignore: cast_nullable_to_non_nullable
as int,bestScore: null == bestScore ? _self.bestScore : bestScore // ignore: cast_nullable_to_non_nullable
as int,totalMatches: null == totalMatches ? _self.totalMatches : totalMatches // ignore: cast_nullable_to_non_nullable
as int,gamesPlayed: null == gamesPlayed ? _self.gamesPlayed : gamesPlayed // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GameProgress].
extension GameProgressPatterns on GameProgress {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameProgress() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameProgress value)  $default,){
final _that = this;
switch (_that) {
case _GameProgress():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameProgress value)?  $default,){
final _that = this;
switch (_that) {
case _GameProgress() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int highestLevel,  int bestScore,  int totalMatches,  int gamesPlayed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameProgress() when $default != null:
return $default(_that.highestLevel,_that.bestScore,_that.totalMatches,_that.gamesPlayed);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int highestLevel,  int bestScore,  int totalMatches,  int gamesPlayed)  $default,) {final _that = this;
switch (_that) {
case _GameProgress():
return $default(_that.highestLevel,_that.bestScore,_that.totalMatches,_that.gamesPlayed);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int highestLevel,  int bestScore,  int totalMatches,  int gamesPlayed)?  $default,) {final _that = this;
switch (_that) {
case _GameProgress() when $default != null:
return $default(_that.highestLevel,_that.bestScore,_that.totalMatches,_that.gamesPlayed);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GameProgress implements GameProgress {
  const _GameProgress({this.highestLevel = 1, this.bestScore = 0, this.totalMatches = 0, this.gamesPlayed = 0});
  factory _GameProgress.fromJson(Map<String, dynamic> json) => _$GameProgressFromJson(json);

@override@JsonKey() final  int highestLevel;
@override@JsonKey() final  int bestScore;
@override@JsonKey() final  int totalMatches;
@override@JsonKey() final  int gamesPlayed;

/// Create a copy of GameProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameProgressCopyWith<_GameProgress> get copyWith => __$GameProgressCopyWithImpl<_GameProgress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GameProgressToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameProgress&&(identical(other.highestLevel, highestLevel) || other.highestLevel == highestLevel)&&(identical(other.bestScore, bestScore) || other.bestScore == bestScore)&&(identical(other.totalMatches, totalMatches) || other.totalMatches == totalMatches)&&(identical(other.gamesPlayed, gamesPlayed) || other.gamesPlayed == gamesPlayed));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,highestLevel,bestScore,totalMatches,gamesPlayed);

@override
String toString() {
  return 'GameProgress(highestLevel: $highestLevel, bestScore: $bestScore, totalMatches: $totalMatches, gamesPlayed: $gamesPlayed)';
}


}

/// @nodoc
abstract mixin class _$GameProgressCopyWith<$Res> implements $GameProgressCopyWith<$Res> {
  factory _$GameProgressCopyWith(_GameProgress value, $Res Function(_GameProgress) _then) = __$GameProgressCopyWithImpl;
@override @useResult
$Res call({
 int highestLevel, int bestScore, int totalMatches, int gamesPlayed
});




}
/// @nodoc
class __$GameProgressCopyWithImpl<$Res>
    implements _$GameProgressCopyWith<$Res> {
  __$GameProgressCopyWithImpl(this._self, this._then);

  final _GameProgress _self;
  final $Res Function(_GameProgress) _then;

/// Create a copy of GameProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? highestLevel = null,Object? bestScore = null,Object? totalMatches = null,Object? gamesPlayed = null,}) {
  return _then(_GameProgress(
highestLevel: null == highestLevel ? _self.highestLevel : highestLevel // ignore: cast_nullable_to_non_nullable
as int,bestScore: null == bestScore ? _self.bestScore : bestScore // ignore: cast_nullable_to_non_nullable
as int,totalMatches: null == totalMatches ? _self.totalMatches : totalMatches // ignore: cast_nullable_to_non_nullable
as int,gamesPlayed: null == gamesPlayed ? _self.gamesPlayed : gamesPlayed // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
