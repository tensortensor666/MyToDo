import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/ui/todo_filter_tab_content.dart';

void main() {
  testWidgets('compact todo filter tabs show accessible count badges', (
    tester,
  ) async {
    const primary = Color(0xFFC96442);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: primary)),
        home: const Scaffold(
          body: Row(
            children: [
              Expanded(
                child: TodoFilterTabContent(
                  label: '当前',
                  count: 3,
                  color: primary,
                  accentColor: primary,
                  selected: true,
                ),
              ),
              Expanded(
                child: TodoFilterTabContent(
                  label: '逾期',
                  count: 12,
                  color: Color(0xFFB53333),
                  accentColor: primary,
                  selected: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('当前'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('逾期'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.bySemanticsLabel('当前任务数量：3'), findsOneWidget);
    expect(find.bySemanticsLabel('逾期任务数量：12'), findsOneWidget);

    final selectedBadge = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('todo-filter-count-当前')),
    );
    final selectedDecoration = selectedBadge.decoration! as BoxDecoration;
    expect(selectedDecoration.color, primary);
  });
}
