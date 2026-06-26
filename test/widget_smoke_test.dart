import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('widget tester can render a minimal app', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('smoke')));

    expect(find.text('smoke'), findsOneWidget);
  });
}
