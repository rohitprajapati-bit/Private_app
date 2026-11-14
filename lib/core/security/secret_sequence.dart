import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import '../utilities/bytes.dart';

/// The owner's hidden entry gesture: a sequence of palette taps in the pause menu.
/// Only a salted hash is stored. This merely hides the entrance — the password is the
/// security boundary.
class SecretSequence {
  const SecretSequence({required this.length, required this.salt, required this.hash});

  final int length;
  final Uint8List salt;
  final Uint8List hash;

  factory SecretSequence.create(List<int> taps) {
    final salt = randomBytes(16);
    return SecretSequence(length: taps.length, salt: salt, hash: _hash(salt, taps));
  }

  bool matches(List<int> taps) => taps.length == length && constantTimeEquals(_hash(salt, taps), hash);

  String encode() => jsonEncode({'n': length, 'salt': base64Encode(salt), 'hash': base64Encode(hash)});

  factory SecretSequence.decode(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return SecretSequence(
      length: map['n'] as int,
      salt: base64Decode(map['salt'] as String),
      hash: base64Decode(map['hash'] as String),
    );
  }

  static Uint8List _hash(Uint8List salt, List<int> taps) =>
      Uint8List.fromList(const DartSha256().hashSync(concatBytes([salt, taps])).bytes);
}

/// Watches palette taps and reports when the most recent taps form the secret sequence.
class SecretSequenceMatcher {
  SecretSequenceMatcher(this._sequence);

  final SecretSequence? _sequence;
  final _recent = <int>[];

  bool add(int paletteIndex) {
    final sequence = _sequence;
    if (sequence == null) return false;
    _recent.add(paletteIndex);
    if (_recent.length > sequence.length) _recent.removeAt(0);
    if (sequence.matches(_recent)) {
      _recent.clear();
      return true;
    }
    return false;
  }

  void reset() => _recent.clear();
}
