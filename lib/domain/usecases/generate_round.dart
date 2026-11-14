import 'dart:math';
import 'package:flutter/painting.dart';

/// One puzzle: find the tile whose colour is identical to [target].
class ColorRound {
  const ColorRound({required this.target, required this.tiles, required this.answerIndex, required this.gridSize});

  final Color target;
  final List<Color> tiles;
  final int answerIndex;
  final int gridSize;
}

/// Level rules for Color Match. Grids grow and decoy shades get closer as levels rise.
class RoundGenerator {
  RoundGenerator([Random? random]) : _random = random ?? Random();

  final Random _random;

  static const roundsPerLevel = 5;

  static int gridSizeFor(int level) => min(2 + (level - 1) ~/ 2, 7);

  static Duration timeFor(int level) => Duration(seconds: 20 + gridSizeFor(level) * 3);

  /// Distance between the target and the decoys in HSL lightness (0..1).
  static double differenceFor(int level) => max(0.035, 0.24 * pow(0.86, level - 1));

  static int pointsFor(int level, int streak) => 10 * level + min(streak, 10) * 2;

  ColorRound next(int level) {
    final size = gridSizeFor(level);
    final count = size * size;
    final delta = differenceFor(level);

    final base = HSLColor.fromAHSL(
      1,
      _random.nextDouble() * 360,
      0.55 + _random.nextDouble() * 0.3,
      0.42 + _random.nextDouble() * 0.16,
    );
    final answer = _random.nextInt(count);
    final tiles = List<Color>.generate(count, (i) {
      if (i == answer) return base.toColor();
      // Decoys differ from the target by at least `delta`, mixing lightness and hue shifts so
      // they also differ slightly from each other.
      final sign = _random.nextBool() ? 1 : -1;
      final lightShift = sign * delta * (1 + _random.nextDouble() * 0.6);
      final hueShift = (_random.nextDouble() - 0.5) * delta * 60;
      return base
          .withLightness((base.lightness + lightShift).clamp(0.08, 0.92))
          .withHue((base.hue + hueShift) % 360)
          .toColor();
    });
    return ColorRound(target: base.toColor(), tiles: tiles, answerIndex: answer, gridSize: size);
  }
}
