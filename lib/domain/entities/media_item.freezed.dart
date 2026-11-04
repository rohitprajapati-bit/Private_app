// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MediaItem {

 String get id; MediaType get type; String get name; String get extension; int get sizeBytes; DateTime get importedAt; String? get albumId; Duration? get duration; int? get width; int? get height;
/// Create a copy of MediaItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaItemCopyWith<MediaItem> get copyWith => _$MediaItemCopyWithImpl<MediaItem>(this as MediaItem, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaItem&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.name, name) || other.name == name)&&(identical(other.extension, extension) || other.extension == extension)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.importedAt, importedAt) || other.importedAt == importedAt)&&(identical(other.albumId, albumId) || other.albumId == albumId)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,name,extension,sizeBytes,importedAt,albumId,duration,width,height);

@override
String toString() {
  return 'MediaItem(id: $id, type: $type, name: $name, extension: $extension, sizeBytes: $sizeBytes, importedAt: $importedAt, albumId: $albumId, duration: $duration, width: $width, height: $height)';
}


}

/// @nodoc
abstract mixin class $MediaItemCopyWith<$Res>  {
  factory $MediaItemCopyWith(MediaItem value, $Res Function(MediaItem) _then) = _$MediaItemCopyWithImpl;
@useResult
$Res call({
 String id, MediaType type, String name, String extension, int sizeBytes, DateTime importedAt, String? albumId, Duration? duration, int? width, int? height
});




}
/// @nodoc
class _$MediaItemCopyWithImpl<$Res>
    implements $MediaItemCopyWith<$Res> {
  _$MediaItemCopyWithImpl(this._self, this._then);

  final MediaItem _self;
  final $Res Function(MediaItem) _then;

/// Create a copy of MediaItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? name = null,Object? extension = null,Object? sizeBytes = null,Object? importedAt = null,Object? albumId = freezed,Object? duration = freezed,Object? width = freezed,Object? height = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as MediaType,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,extension: null == extension ? _self.extension : extension // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,importedAt: null == importedAt ? _self.importedAt : importedAt // ignore: cast_nullable_to_non_nullable
as DateTime,albumId: freezed == albumId ? _self.albumId : albumId // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [MediaItem].
extension MediaItemPatterns on MediaItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MediaItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MediaItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MediaItem value)  $default,){
final _that = this;
switch (_that) {
case _MediaItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MediaItem value)?  $default,){
final _that = this;
switch (_that) {
case _MediaItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  MediaType type,  String name,  String extension,  int sizeBytes,  DateTime importedAt,  String? albumId,  Duration? duration,  int? width,  int? height)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MediaItem() when $default != null:
return $default(_that.id,_that.type,_that.name,_that.extension,_that.sizeBytes,_that.importedAt,_that.albumId,_that.duration,_that.width,_that.height);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  MediaType type,  String name,  String extension,  int sizeBytes,  DateTime importedAt,  String? albumId,  Duration? duration,  int? width,  int? height)  $default,) {final _that = this;
switch (_that) {
case _MediaItem():
return $default(_that.id,_that.type,_that.name,_that.extension,_that.sizeBytes,_that.importedAt,_that.albumId,_that.duration,_that.width,_that.height);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  MediaType type,  String name,  String extension,  int sizeBytes,  DateTime importedAt,  String? albumId,  Duration? duration,  int? width,  int? height)?  $default,) {final _that = this;
switch (_that) {
case _MediaItem() when $default != null:
return $default(_that.id,_that.type,_that.name,_that.extension,_that.sizeBytes,_that.importedAt,_that.albumId,_that.duration,_that.width,_that.height);case _:
  return null;

}
}

}

/// @nodoc


class _MediaItem extends MediaItem {
  const _MediaItem({required this.id, required this.type, required this.name, required this.extension, required this.sizeBytes, required this.importedAt, this.albumId, this.duration, this.width, this.height}): super._();
  

@override final  String id;
@override final  MediaType type;
@override final  String name;
@override final  String extension;
@override final  int sizeBytes;
@override final  DateTime importedAt;
@override final  String? albumId;
@override final  Duration? duration;
@override final  int? width;
@override final  int? height;

/// Create a copy of MediaItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MediaItemCopyWith<_MediaItem> get copyWith => __$MediaItemCopyWithImpl<_MediaItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MediaItem&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.name, name) || other.name == name)&&(identical(other.extension, extension) || other.extension == extension)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.importedAt, importedAt) || other.importedAt == importedAt)&&(identical(other.albumId, albumId) || other.albumId == albumId)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,name,extension,sizeBytes,importedAt,albumId,duration,width,height);

@override
String toString() {
  return 'MediaItem(id: $id, type: $type, name: $name, extension: $extension, sizeBytes: $sizeBytes, importedAt: $importedAt, albumId: $albumId, duration: $duration, width: $width, height: $height)';
}


}

/// @nodoc
abstract mixin class _$MediaItemCopyWith<$Res> implements $MediaItemCopyWith<$Res> {
  factory _$MediaItemCopyWith(_MediaItem value, $Res Function(_MediaItem) _then) = __$MediaItemCopyWithImpl;
@override @useResult
$Res call({
 String id, MediaType type, String name, String extension, int sizeBytes, DateTime importedAt, String? albumId, Duration? duration, int? width, int? height
});




}
/// @nodoc
class __$MediaItemCopyWithImpl<$Res>
    implements _$MediaItemCopyWith<$Res> {
  __$MediaItemCopyWithImpl(this._self, this._then);

  final _MediaItem _self;
  final $Res Function(_MediaItem) _then;

/// Create a copy of MediaItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? name = null,Object? extension = null,Object? sizeBytes = null,Object? importedAt = null,Object? albumId = freezed,Object? duration = freezed,Object? width = freezed,Object? height = freezed,}) {
  return _then(_MediaItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as MediaType,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,extension: null == extension ? _self.extension : extension // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,importedAt: null == importedAt ? _self.importedAt : importedAt // ignore: cast_nullable_to_non_nullable
as DateTime,albumId: freezed == albumId ? _self.albumId : albumId // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
