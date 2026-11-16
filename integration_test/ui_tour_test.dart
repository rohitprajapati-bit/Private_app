import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:private_app/core/storage/vault_paths.dart';
import 'package:private_app/domain/entities/media_item.dart';
import 'package:private_app/domain/repositories/media_repository.dart';
import 'package:private_app/injection.dart';
import 'package:private_app/main.dart' as app;
import 'package:private_app/presentation/common/palette_keypad.dart';
import 'package:private_app/presentation/game/game_screen.dart';
import 'package:private_app/presentation/vault/vault_providers.dart';
import 'package:private_app/routes/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _password = 'Correct-Horse-9';
const _sequence = [0, 2, 3, 5];

/// Walks every screen and pauses on each, printing `SHOT:<name>` so a script outside the
/// app can take a simulator screenshot. Not a correctness test — a design review aid.
/// Wipes the app's data: run it on a throwaway simulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> wait(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> until(WidgetTester tester, Finder finder, {int seconds = 60}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await wait(tester, 100);
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Timed out waiting for $finder');
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await wait(tester, 1200);
    debugPrint('SHOT:$name');
    await wait(tester, 2500);
  }

  Future<void> tapPalette(WidgetTester tester, List<int> taps) async {
    for (final i in taps) {
      final swatches = find.descendant(of: find.byType(PaletteKeypad), matching: find.byType(GestureDetector));
      await tester.tap(swatches.at(i));
      await wait(tester, 300);
    }
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  Future<void> go(WidgetTester tester, String location, {Object? extra}) async {
    container(tester).read(routerProvider).go(location, extra: extra);
    await wait(tester, 400);
  }

  Future<File> makePng(String name, Color a, Color b) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const rect = Rect.fromLTWH(0, 0, 600, 600);
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [a, b]).createShader(rect));
    canvas.drawCircle(const Offset(420, 180), 90, Paint()..color = Colors.white.withValues(alpha: 0.7));
    final image = await recorder.endRecording().toImage(600, 600);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await Directory.systemTemp.createTemp('tour');
    return File(p.join(dir.path, name))..writeAsBytesSync(png!.buffer.asUint8List());
  }

  testWidgets('ui tour', (tester) async {
    final paths = await VaultPaths.resolve();
    if (await paths.root.exists()) await paths.root.delete(recursive: true);
    await (await SharedPreferences.getInstance()).clear();
    await app.main();

    await until(tester, find.text('Set up your private space'));
    await shot(tester, '01-setup-intro');
    await tester.tap(find.byType(Checkbox));
    await wait(tester, 200);
    await tester.tap(find.text('Continue'));
    await until(tester, find.text('Create a password'));
    await tester.enterText(find.byType(TextField).at(0), _password);
    await tester.enterText(find.byType(TextField).at(1), _password);
    await shot(tester, '02-setup-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await until(tester, find.text('Choose your secret colours'));
    await tapPalette(tester, _sequence);
    await shot(tester, '03-setup-colours');
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await wait(tester, 300);
    await tapPalette(tester, _sequence);
    await until(tester, find.text('Play'), seconds: 90);
    await shot(tester, '04-home');

    await go(tester, Routes.levels);
    await shot(tester, '05-levels');
    await go(tester, Routes.gameSettings);
    await shot(tester, '06-game-settings');
    await go(tester, Routes.home);
    await tester.tap(find.text('Play'));
    await until(tester, find.byType(GameScreen));
    await shot(tester, '07-game');
    await tester.tap(find.byTooltip('Pause'));
    await until(tester, find.text('Tile style'));
    await shot(tester, '08-pause');
    await tapPalette(tester, _sequence);
    await until(tester, find.text('Enter password'));
    await shot(tester, '09-unlock');
    await tester.enterText(find.byType(TextField), _password);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await until(tester, find.text('Private'));

    // Seed a few photos so the grid looks like real use.
    final colours = [
      (Colors.orange, Colors.pink),
      (Colors.blue, Colors.teal),
      (Colors.purple, Colors.indigo),
      (Colors.green, Colors.lime),
      (Colors.red, Colors.amber),
      (Colors.cyan, Colors.blueGrey),
    ];
    final sources = <ImportSource>[];
    for (final (i, (a, b)) in colours.indexed) {
      final file = await makePng('photo_$i.png', a, b);
      sources.add(ImportSource(path: file.path, name: 'Photo ${i + 1}'));
    }
    await tester.runAsync(() => container(tester).read(mediaRepositoryProvider).import(sources, MediaType.photo).last);
    await tester.runAsync(() => container(tester).read(vaultLibraryProvider.notifier).reload());
    await shot(tester, '10-vault-photos');

    await tester.longPress(find.byType(GestureDetector).at(10));
    await shot(tester, '11-vault-selecting');
    await tester.tap(find.byTooltip('Cancel'));
    await wait(tester, 300);

    for (final (tab, name) in [('Videos', '12-vault-videos'), ('Albums', '13-vault-albums'), ('Shared', '14-vault-shared')]) {
      await tester.tap(find.text(tab).last);
      await shot(tester, name);
    }
    await tester.tap(find.text('Photos').last);
    await wait(tester, 300);

    final first = (await tester.runAsync(() => container(tester).read(vaultLibraryProvider.future)))!.items.first;
    await go(tester, Routes.photo(Routes.vault, first.id));
    await shot(tester, '15-photo-viewer');

    await go(tester, Routes.vaultSettings);
    await shot(tester, '16-vault-settings');
    await go(tester, Routes.sharing);
    await shot(tester, '17-sharing');
    await go(tester, Routes.send, extra: const <String>[]);
    await shot(tester, '18-send-picker');
    await go(tester, Routes.send, extra: [first.id]);
    await shot(tester, '19-send');
    await go(tester, Routes.receive);
    await shot(tester, '20-receive');
    await go(tester, Routes.vault);
    await wait(tester, 500);
    debugPrint('SHOT:done');
    await wait(tester, 1000);
  });
}
