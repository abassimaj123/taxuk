import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxuk/screens/cgt_screen.dart';

void main() {
  // Regression test for the investments shell bug: CGTScreen was always
  // instantiated with `const CGTScreen()`, ignoring the gross income
  // already available from the Income Tax tab (via grossIncomeNotifier),
  // so it silently fell back to its hardcoded default of 35000.
  testWidgets(
    'CGTScreen pre-fills the gross income field from initialGrossIncome '
    'instead of defaulting to 35000',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CGTScreen(initialGrossIncome: 82000),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, '82000');
      expect(field.controller!.text, isNot('35000'));
    },
  );

  testWidgets(
    'CGTScreen falls back to 35000 when initialGrossIncome is null',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CGTScreen(),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, '35000');
    },
  );
}
