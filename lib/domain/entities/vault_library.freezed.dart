// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'vault_library.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VaultLibrary {

 List<MediaItem> get items; List<Album> get albums;
/// Create a copy of VaultLibrary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultLibraryCopyWith<VaultLibrary> get copyWith => _$VaultLibraryCopyWithImpl<VaultLibrary>(this as VaultLibrary, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultLibrary&&const DeepCollectionEquality().equals(other.items, items)&&const DeepCollectionEquality().equals(other.albums, albums));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),const DeepCollectionEquality().hash(albums));

@override
String toString() {
  return 'VaultLibrary(items: $items, albums: $albums)';
}


}

/// @nodoc
abstract mixin class $VaultLibraryCopyWith<$Res>  {
  factory $VaultLibraryCopyWith(VaultLibrary value, $Res Function(VaultLibrary) _then) = _$VaultLibraryCopyWithImpl;
@useResult
$Res call({
 List<MediaItem> items, List<Album> albums
});




}
/// @nodoc
class _$VaultLibraryCopyWithImpl<$Res>
    implements $VaultLibraryCopyWith<$Res> {
  _$VaultLibraryCopyWithImpl(this._self, this._then);

  final VaultLibrary _self;
  final $Res Function(VaultLibrary) _then;

/// Create a copy of VaultLibrary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? albums = null,}) {
  return _then(_self.copyWith(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<MediaItem>,albums: null == albums ? _self.albums : albums // ignore: cast_nullable_to_non_nullable
as List<Album>,
  ));
}

}


/// Adds pattern-matching-related methods to [VaultLibrary].
extension VaultLibraryPatterns on VaultLibrary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VaultLibrary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VaultLibrary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VaultLibrary value)  $default,){
final _that = this;
switch (_that) {
case _VaultLibrary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VaultLibrary value)?  $default,){
final _that = this;
switch (_that) {
case _VaultLibrary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<MediaItem> items,  List<Album> albums)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VaultLibrary() when $default != null:
return $default(_that.items,_that.albums);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<MediaItem> items,  List<Album> albums)  $default,) {final _that = this;
switch (_that) {
case _VaultLibrary():
return $default(_that.items,_that.albums);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<MediaItem> items,  List<Album> albums)?  $default,) {final _that = this;
switch (_that) {
case _VaultLibrary() when $default != null:
return $default(_that.items,_that.albums);case _:
  return null;

}
}

}

/// @nodoc


class _VaultLibrary extends VaultLibrary {
  const _VaultLibrary({final  List<MediaItem> items = const [], final  List<Album> albums = const []}): _items = items,_albums = albums,super._();
  

 final  List<MediaItem> _items;
@override@JsonKey() List<MediaItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

 final  List<Album> _albums;
@override@JsonKey() List<Album> get albums {
  if (_albums is EqualUnmodifiableListView) return _albums;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_albums);
}


/// Create a copy of VaultLibrary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VaultLibraryCopyWith<_VaultLibrary> get copyWith => __$VaultLibraryCopyWithImpl<_VaultLibrary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _VaultLibrary&&const DeepCollectionEquality().equals(other._items, _items)&&const DeepCollectionEquality().equals(other._albums, _albums));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),const DeepCollectionEquality().hash(_albums));

@override
String toString() {
  return 'VaultLibrary(items: $items, albums: $albums)';
}


}

/// @nodoc
abstract mixin class _$VaultLibraryCopyWith<$Res> implements $VaultLibraryCopyWith<$Res> {
  factory _$VaultLibraryCopyWith(_VaultLibrary value, $Res Function(_VaultLibrary) _then) = __$VaultLibraryCopyWithImpl;
@override @useResult
$Res call({
 List<MediaItem> items, List<Album> albums
});




}
/// @nodoc
class __$VaultLibraryCopyWithImpl<$Res>
    implements _$VaultLibraryCopyWith<$Res> {
  __$VaultLibraryCopyWithImpl(this._self, this._then);

  final _VaultLibrary _self;
  final $Res Function(_VaultLibrary) _then;

/// Create a copy of VaultLibrary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,Object? albums = null,}) {
  return _then(_VaultLibrary(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<MediaItem>,albums: null == albums ? _self._albums : albums // ignore: cast_nullable_to_non_nullable
as List<Album>,
  ));
}


}

// dart format on
