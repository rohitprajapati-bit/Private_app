import 'package:freezed_annotation/freezed_annotation.dart';

part 'album.freezed.dart';

@freezed
abstract class Album with _$Album {
  const factory Album({required String id, required String name, required DateTime createdAt}) = _Album;
}
