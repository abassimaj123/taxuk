import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:taxuk/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('TaxUK integration tests', () {
    testWidgets('App launches without crashing', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Main shell is visible', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(Scaffold), findsWidgets);
    });
  });
}
