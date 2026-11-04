// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'game_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GameState {

 int get level; ColorRound? get round; int get roundInLevel; int get score; int get streak; Duration get timeLeft; Duration get levelTime; GameStatus get status;/// Incremented on each wrong tap so the grid can replay its shake animation.
 int get mistakes; int? get wrongIndex;
/// Create a copy of GameState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameStateCopyWith<GameState> get copyWith => _$GameStateCopyWithImpl<GameState>(this as GameState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameState&&(identical(other.level, level) || other.level == level)&&(identical(other.round, round) || other.round == round)&&(identical(other.roundInLevel, roundInLevel) || other.roundInLevel == roundInLevel)&&(identical(other.score, score) || other.score == score)&&(identical(other.streak, streak) || other.streak == streak)&&(identical(other.timeLeft, timeLeft) || other.timeLeft == timeLeft)&&(identical(other.levelTime, levelTime) || other.levelTime == levelTime)&&(identical(other.status, status) || other.status == status)&&(identical(other.mistakes, mistakes) || other.mistakes == mistakes)&&(identical(other.wrongIndex, wrongIndex) || other.wrongIndex == wrongIndex));
}


@override
int get hashCode => Object.hash(runtimeType,level,round,roundInLevel,score,streak,timeLeft,levelTime,status,mistakes,wrongIndex);

@override
String toString() {
  return 'GameState(level: $level, round: $round, roundInLevel: $roundInLevel, score: $score, streak: $streak, timeLeft: $timeLeft, levelTime: $levelTime, status: $status, mistakes: $mistakes, wrongIndex: $wrongIndex)';
}


}

/// @nodoc
abstract mixin class $GameStateCopyWith<$Res>  {
  factory $GameStateCopyWith(GameState value, $Res Function(GameState) _then) = _$GameStateCopyWithImpl;
@useResult
$Res call({
 int level, ColorRound? round, int roundInLevel, int score, int streak, Duration timeLeft, Duration levelTime, GameStatus status, int mistakes, int? wrongIndex
});




}
/// @nodoc
class _$GameStateCopyWithImpl<$Res>
    implements $GameStateCopyWith<$Res> {
  _$GameStateCopyWithImpl(this._self, this._then);

  final GameState _self;
  final $Res Function(GameState) _then;

/// Create a copy of GameState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? level = null,Object? round = freezed,Object? roundInLevel = null,Object? score = null,Object? streak = null,Object? timeLeft = null,Object? levelTime = null,Object? status = null,Object? mistakes = null,Object? wrongIndex = freezed,}) {
  return _then(_self.copyWith(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int,round: freezed == round ? _self.round : round // ignore: cast_nullable_to_non_nullable
as ColorRound?,roundInLevel: null == roundInLevel ? _self.roundInLevel : roundInLevel // ignore: cast_nullable_to_non_nullable
as int,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as int,streak: null == streak ? _self.streak : streak // ignore: cast_nullable_to_non_nullable
as int,timeLeft: null == timeLeft ? _self.timeLeft : timeLeft // ignore: cast_nullable_to_non_nullable
as Duration,levelTime: null == levelTime ? _self.levelTime : levelTime // ignore: cast_nullable_to_non_nullable
as Duration,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as GameStatus,mistakes: null == mistakes ? _self.mistakes : mistakes // ignore: cast_nullable_to_non_nullable
as int,wrongIndex: freezed == wrongIndex ? _self.wrongIndex : wrongIndex // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [GameState].
extension GameStatePatterns on GameState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameState value)  $default,){
final _that = this;
switch (_that) {
case _GameState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameState value)?  $default,){
final _that = this;
switch (_that) {
case _GameState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int level,  ColorRound? round,  int roundInLevel,  int score,  int streak,  Duration timeLeft,  Duration levelTime,  GameStatus status,  int mistakes,  int? wrongIndex)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameState() when $default != null:
return $default(_that.level,_that.round,_that.roundInLevel,_that.score,_that.streak,_that.timeLeft,_that.levelTime,_that.status,_that.mistakes,_that.wrongIndex);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int level,  ColorRound? round,  int roundInLevel,  int score,  int streak,  Duration timeLeft,  Duration levelTime,  GameStatus status,  int mistakes,  int? wrongIndex)  $default,) {final _that = this;
switch (_that) {
case _GameState():
return $default(_that.level,_that.round,_that.roundInLevel,_that.score,_that.streak,_that.timeLeft,_that.levelTime,_that.status,_that.mistakes,_that.wrongIndex);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int level,  ColorRound? round,  int roundInLevel,  int score,  int streak,  Duration timeLeft,  Duration levelTime,  GameStatus status,  int mistakes,  int? wrongIndex)?  $default,) {final _that = this;
switch (_that) {
case _GameState() when $default != null:
return $default(_that.level,_that.round,_that.roundInLevel,_that.score,_that.streak,_that.timeLeft,_that.levelTime,_that.status,_that.mistakes,_that.wrongIndex);case _:
  return null;

}
}

}

/// @nodoc


class _GameState implements GameState {
  const _GameState({this.level = 1, this.round, this.roundInLevel = 0, this.score = 0, this.streak = 0, this.timeLeft = Duration.zero, this.levelTime = const Duration(seconds: 1), this.status = GameStatus.ready, this.mistakes = 0, this.wrongIndex});
  

@override@JsonKey() final  int level;
@override final  ColorRound? round;
@override@JsonKey() final  int roundInLevel;
@override@JsonKey() final  int score;
@override@JsonKey() final  int streak;
@override@JsonKey() final  Duration timeLeft;
@override@JsonKey() final  Duration levelTime;
@override@JsonKey() final  GameStatus status;
/// Incremented on each wrong tap so the grid can replay its shake animation.
@override@JsonKey() final  int mistakes;
@override final  int? wrongIndex;

/// Create a copy of GameState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameStateCopyWith<_GameState> get copyWith => __$GameStateCopyWithImpl<_GameState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameState&&(identical(other.level, level) || other.level == level)&&(identical(other.round, round) || other.round == round)&&(identical(other.roundInLevel, roundInLevel) || other.roundInLevel == roundInLevel)&&(identical(other.score, score) || other.score == score)&&(identical(other.streak, streak) || other.streak == streak)&&(identical(other.timeLeft, timeLeft) || other.timeLeft == timeLeft)&&(identical(other.levelTime, levelTime) || other.levelTime == levelTime)&&(identical(other.status, status) || other.status == status)&&(identical(other.mistakes, mistakes) || other.mistakes == mistakes)&&(identical(other.wrongIndex, wrongIndex) || other.wrongIndex == wrongIndex));
}


@override
int get hashCode => Object.hash(runtimeType,level,round,roundInLevel,score,streak,timeLeft,levelTime,status,mistakes,wrongIndex);

@override
String toString() {
  return 'GameState(level: $level, round: $round, roundInLevel: $roundInLevel, score: $score, streak: $streak, timeLeft: $timeLeft, levelTime: $levelTime, status: $status, mistakes: $mistakes, wrongIndex: $wrongIndex)';
}


}

/// @nodoc
abstract mixin class _$GameStateCopyWith<$Res> implements $GameStateCopyWith<$Res> {
  factory _$GameStateCopyWith(_GameState value, $Res Function(_GameState) _then) = __$GameStateCopyWithImpl;
@override @useResult
$Res call({
 int level, ColorRound? round, int roundInLevel, int score, int streak, Duration timeLeft, Duration levelTime, GameStatus status, int mistakes, int? wrongIndex
});




}
/// @nodoc
class __$GameStateCopyWithImpl<$Res>
    implements _$GameStateCopyWith<$Res> {
  __$GameStateCopyWithImpl(this._self, this._then);

  final _GameState _self;
  final $Res Function(_GameState) _then;

/// Create a copy of GameState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? level = null,Object? round = freezed,Object? roundInLevel = null,Object? score = null,Object? streak = null,Object? timeLeft = null,Object? levelTime = null,Object? status = null,Object? mistakes = null,Object? wrongIndex = freezed,}) {
  return _then(_GameState(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int,round: freezed == round ? _self.round : round // ignore: cast_nullable_to_non_nullable
as ColorRound?,roundInLevel: null == roundInLevel ? _self.roundInLevel : roundInLevel // ignore: cast_nullable_to_non_nullable
as int,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as int,streak: null == streak ? _self.streak : streak // ignore: cast_nullable_to_non_nullable
as int,timeLeft: null == timeLeft ? _self.timeLeft : timeLeft // ignore: cast_nullable_to_non_nullable
as Duration,levelTime: null == levelTime ? _self.levelTime : levelTime // ignore: cast_nullable_to_non_nullable
as Duration,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as GameStatus,mistakes: null == mistakes ? _self.mistakes : mistakes // ignore: cast_nullable_to_non_nullable
as int,wrongIndex: freezed == wrongIndex ? _self.wrongIndex : wrongIndex // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
