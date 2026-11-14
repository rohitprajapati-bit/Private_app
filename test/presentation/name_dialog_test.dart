import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_app/presentation/vault/media_actions.dart';

void main() {
  Future<void> open(WidgetTester tester, ValueChanged<String?> onResult, {String initial = ''}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(await MediaActions.promptName(context, title: 'New album', initial: initial)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving returns the name and survives the closing animation', (tester) async {
    String? result;
    await open(tester, (r) => result = r);
    await tester.enterText(find.byType(TextField), '  rohit ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle(); // runs the exit animation that used the disposed controller
    expect(tester.takeException(), isNull);
    expect(result, 'rohit');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancel and blank names return null; rename starts from the current name', (tester) async {
    String? result = 'unset';
    await open(tester, (r) => result = r, initial: 'Trips');
    expect(find.text('Trips'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
