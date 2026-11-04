import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// Row of palette swatches. Used as the game's "tile style" picker and as the keypad for
/// recording the secret sequence.
class PaletteKeypad extends StatelessWidget {
  const PaletteKeypad({super.key, required this.onTap, this.selected, this.size = 44});

  final ValueChanged<int> onTap;
  final int? selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var i = 0; i < AppConstants.palette.length; i++)
          Semantics(
            button: true,
            label: 'Style ${i + 1}',
            child: GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: AppConstants.palette[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: selected == i ? 3 : 0),
                  boxShadow: [
                    BoxShadow(color: AppConstants.palette[i].withValues(alpha: 0.45), blurRadius: 10),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Filled/empty dots showing how many taps of a sequence have been entered.
class SequenceDots extends StatelessWidget {
  const SequenceDots({super.key, required this.taps, required this.max});

  final List<int> taps;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < max; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < taps.length ? AppConstants.palette[taps[i]] : Colors.white12,
            ),
          ),
      ],
    );
  }
}
