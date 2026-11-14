import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'palette_keypad.dart';

/// Records a 4–6 tap colour sequence, then asks for it again to confirm.
class SequenceRecorder extends StatefulWidget {
  const SequenceRecorder({super.key, required this.onConfirmed});

  final ValueChanged<List<int>> onConfirmed;

  @override
  State<SequenceRecorder> createState() => _SequenceRecorderState();
}

class _SequenceRecorderState extends State<SequenceRecorder> {
  final _taps = <int>[];
  List<int>? _first;
  String? _error;

  void _tap(int index) {
    if (_taps.length >= AppConstants.secretSequenceMaxLength) return;
    setState(() {
      _error = null;
      _taps.add(index);
    });
    final first = _first;
    if (first != null && _taps.length == first.length) _checkConfirmation(first);
  }

  void _checkConfirmation(List<int> first) {
    if (_listEquals(first, _taps)) {
      widget.onConfirmed(List.of(_taps));
    } else {
      setState(() {
        _error = "Sequences didn't match. Start again.";
        _first = null;
        _taps.clear();
      });
    }
  }

  void _next() => setState(() {
    _first = List.of(_taps);
    _taps.clear();
  });

  @override
  Widget build(BuildContext context) {
    final confirming = _first != null;
    final length = _first?.length ?? AppConstants.secretSequenceMaxLength;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          confirming ? 'Tap the same sequence again' : 'Tap 4–6 colours in order',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 16),
        SequenceDots(taps: _taps, max: length),
        const SizedBox(height: 8),
        Text(
          _taps.isEmpty ? ' ' : _taps.map((i) => i + 1).join(' · '),
          style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1),
        ),
        const SizedBox(height: 20),
        PaletteKeypad(onTap: _tap, size: 48),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _taps.isEmpty ? null : () => setState(_taps.clear),
              child: const Text('Clear'),
            ),
            if (!confirming)
              FilledButton(
                onPressed: _taps.length >= AppConstants.secretSequenceMinLength ? _next : null,
                child: const Text('Next'),
              ),
          ],
        ),
      ],
    );
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
