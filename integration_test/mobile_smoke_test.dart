import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:short_circuit/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android loads the packaged C++ engine and solves a circuit', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    // Use a known example even when the emulator has a recovered workspace.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Starter examples'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Voltage divider').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('run-simulation')));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('nav-results')));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    await tester.scrollUntilVisible(find.text('COMPONENT READINGS'), 100);
    expect(find.text('COMPONENT READINGS'), findsOneWidget);
    expect(find.text('Check your circuit'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Save project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Android smoke test');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Android smoke test'), 150);
    expect(find.text('Android smoke test'), findsOneWidget);
  });
}
