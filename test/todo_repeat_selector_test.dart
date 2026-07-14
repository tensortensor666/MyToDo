import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/ui/todo_repeat_selector.dart';

void main() {
  testWidgets('daily task can switch to no repeat with a clear consequence', (
    tester,
  ) async {
    TodoRepeatOption selected = TodoRepeatOption.daily;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC96442)),
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return TodoRepeatSelector(
                    value: selected,
                    startedAsDaily: true,
                    accentColor: const Color(0xFFC96442),
                    warningColor: const Color(0xFFEAB308),
                    onChanged: (value) {
                      setState(() => selected = value);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('每天重复'), findsOneWidget);
    expect(find.text('每天自动生成一条新任务。'), findsOneWidget);

    await tester.tap(find.text('不重复'));
    await tester.pumpAndSettle();

    expect(selected, TodoRepeatOption.none);
    expect(find.text('将取消每天重复'), findsOneWidget);
    expect(find.text('保存后停止生成后续任务，当前这条任务仍会保留。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
