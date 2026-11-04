import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_app/domain/usecases/generate_round.dart';
import 'package:private_app/domain/usecases/password_policy.dart';

void main() {
  test('every round has exactly one tile identical to the target', () {
    final generator = RoundGenerator(Random(42));
    for (var level = 1; level <= 40; level++) {
      for (var i = 0; i < 20; i++) {
        final round = generator.next(level);
        expect(round.tiles.length, round.gridSize * round.gridSize);
        expect(round.tiles[round.answerIndex], round.target);
        final matches = round.tiles.where((c) => c == round.target).length;
        expect(matches, 1, reason: 'level $level');
      }
    }
  });

  test('difficulty rises with level', () {
    expect(RoundGenerator.gridSizeFor(1), 2);
    expect(RoundGenerator.gridSizeFor(40), 7);
    expect(RoundGenerator.differenceFor(1), greaterThan(RoundGenerator.differenceFor(10)));
    expect(RoundGenerator.differenceFor(100), greaterThanOrEqualTo(0.035));
  });

  test('password policy', () {
    expect(validateNewPassword('short', 'short'), isNotNull);
    expect(validateNewPassword('long enough', 'long enougH'), 'Passwords do not match.');
    expect(validateNewPassword('long enough', 'long enough'), isNull);
    expect(passwordStrength('aaaaaaaa'), PasswordStrength.weak);
    expect(passwordStrength('Tr0ub4dor&3x'), PasswordStrength.strong);
  });
}
