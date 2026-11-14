import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:private_app/core/storage/vault_paths.dart';
import 'package:private_app/injection.dart';
import 'package:private_app/main.dart' as app;
import 'package:private_app/presentation/common/palette_keypad.dart';
import 'package:private_app/presentation/game/game_controller.dart';
import 'package:private_app/presentation/game/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _password = 'Correct-Horse-9';
const _sequence = [0, 2, 3, 5];
final _clock = Stopwatch()..start();

/// Drives the real app UI end to end: first-launch setup, playing, the hidden entrance,
/// wrong/right password, albums, background auto-lock and re-entry.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(WidgetTester tester, Finder finder, {int seconds = 30}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('${_clock.elapsed.inSeconds}s STEP: TIMEOUT waiting for $finder');
    throw TestFailure('Timed out waiting for $finder');
  }

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapPalette(WidgetTester tester, List<int> taps) async {
    for (final i in taps) {
      final swatches = find.descendant(of: find.byType(PaletteKeypad), matching: find.byType(GestureDetector));
      await tester.tap(swatches.at(i));
      await settle(tester, 300);
    }
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  Future<void> sendToBackgroundAndBack(WidgetTester tester) async {
    final binding = tester.binding;
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await settle(tester);
  }

  Future<void> openPasswordScreen(WidgetTester tester) async {
    await pumpUntil(tester, find.text('Play'));
    await tester.tap(find.text('Play'));
    await pumpUntil(tester, find.byType(GameScreen));
    await settle(tester);
    await tester.tap(find.byTooltip('Pause'));
    await pumpUntil(tester, find.text('Tile style'));
    await tapPalette(tester, _sequence);
    await pumpUntil(tester, find.text('Enter password'));
  }

  Future<void> unlock(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
  }

  testWidgets('setup → game → hidden entry → vault → auto-lock → re-entry', (tester) async {
    // Fresh install: no vault files (main() then wipes leftover Keychain items) and no progress.
    final paths = await VaultPaths.resolve();
    if (await paths.root.exists()) await paths.root.delete(recursive: true);
    await (await SharedPreferences.getInstance()).clear();

    debugPrint('${_clock.elapsed.inSeconds}s STEP: launching app');
    await app.main();
    debugPrint('${_clock.elapsed.inSeconds}s STEP: app launched');
    await pumpUntil(tester, find.text('Set up your private space'));

    // --- Setup ---

    debugPrint('${_clock.elapsed.inSeconds}s STEP: Setup');
    await tester.tap(find.byType(Checkbox));
    await settle(tester, 200);
    await tester.tap(find.text('Continue'));
    await pumpUntil(tester, find.text('Create a password'));
    await tester.enterText(find.byType(TextField).at(0), _password);
    await tester.enterText(find.byType(TextField).at(1), 'mismatch');
    await settle(tester, 300);
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(1), _password);
    await settle(tester, 300); // Next enables once both fields match
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await pumpUntil(tester, find.text('Choose your secret colours'));
    await tapPalette(tester, _sequence);
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await settle(tester, 300);
    await tapPalette(tester, _sequence); // confirmation auto-submits
    // Key generation (Argon2id) runs now, then home.
    await pumpUntil(tester, find.text('Play'), seconds: 60);

    // --- The game plays normally ---

    debugPrint('${_clock.elapsed.inSeconds}s STEP: The game plays normally');
    await tester.tap(find.text('Play'));
    await pumpUntil(tester, find.byType(GameScreen));
    await settle(tester);
    var game = container(tester).read(gameControllerProvider);
    expect(game.status, GameStatus.playing);
    expect(game.round!.gridSize, 2);
    final wrong = (game.round!.answerIndex + 1) % 4;
    await tester.tap(find.byKey(ValueKey('1-0-$wrong')));
    await settle(tester, 200);
    game = container(tester).read(gameControllerProvider);
    expect(game.score, 0);
    expect(game.mistakes, 1);
    await tester.tap(find.byKey(ValueKey('1-0-${game.round!.answerIndex}')));
    await settle(tester, 200);
    expect(container(tester).read(gameControllerProvider).score, greaterThan(0));

    // --- A wrong colour sequence does nothing ---

    debugPrint('${_clock.elapsed.inSeconds}s STEP: A wrong colour sequence does nothing');
    await tester.tap(find.byTooltip('Pause'));
    await pumpUntil(tester, find.text('Tile style'));
    await tapPalette(tester, [1, 1, 4, 4]);
    expect(find.text('Enter password'), findsNothing);

    // --- Correct sequence → password screen; wrong then right password ---

    debugPrint('${_clock.elapsed.inSeconds}s STEP: Correct sequence → password screen; wrong then right password');
    await tapPalette(tester, _sequence);
    await pumpUntil(tester, find.text('Enter password'));
    await unlock(tester, 'wrong-password');
    await pumpUntil(tester, find.text('Incorrect password.'));
    await unlock(tester, _password);
    await pumpUntil(tester, find.text('Private'));
    expect(container(tester).read(sessionProvider).isUnlocked, isTrue);

    // --- Albums ---

    debugPrint('${_clock.elapsed.inSeconds}s STEP: Albums');
    await tester.tap(find.text('Albums'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New album'));
    await pumpUntil(tester, find.byType(AlertDialog));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Trips');
    await tester.tap(find.text('Save'));
    await pumpUntil(tester, find.text('Trips'));
    await settle(tester, 800); // dialog exit animation (previously crashed here)
    expect(tester.takeException(), isNull);

    // --- Going to the background locks the vault and returns to the game ---

    debugPrint('${_clock.elapsed.inSeconds}s STEP: Going to the background locks the vault and returns to the game');
    await sendToBackgroundAndBack(tester);
    expect(container(tester).read(sessionProvider).isUnlocked, isFalse);
    await pumpUntil(tester, find.text('Play'));
    expect(find.text('Private'), findsNothing);

    // --- Re-entry shows the saved album again ---

    debugPrint('${_clock.elapsed.inSeconds}s STEP: Re-entry shows the saved album again');
    await openPasswordScreen(tester);
    await unlock(tester, _password);
    await pumpUntil(tester, find.text('Private'));
    await tester.tap(find.text('Albums'));
    await pumpUntil(tester, find.text('Trips'));

    // --- Lock button ---

    debugPrint('${_clock.elapsed.inSeconds}s STEP: Lock button');
    await tester.tap(find.byTooltip('Lock'));
    await pumpUntil(tester, find.text('Play'));
    expect(container(tester).read(sessionProvider).isUnlocked, isFalse);
  });
}
