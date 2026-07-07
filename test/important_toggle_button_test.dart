import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/ui/important_toggle_button.dart';

void main() {
  testWidgets('important toggle button switches icon and calls callback', (
    tester,
  ) async {
    var important = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return ImportantToggleButton(
              important: important,
              onPressed: () => setState(() => important = !important),
            );
          },
        ),
      ),
    );

    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNothing);

    await tester.tap(find.byType(ImportantToggleButton));
    await tester.pump();

    expect(important, isTrue);
    expect(find.byIcon(Icons.star_border_rounded), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });
}
