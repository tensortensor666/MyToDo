import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/ui/todo_mobile_status_overview.dart';
import 'package:mytodo/src/ui/todo_view_filter.dart';

void main() {
  testWidgets(
    'mobile overview keeps overdue inside current with a priority entry',
    (tester) async {
      var selectedFilter = TodoViewFilter.active;

      Widget buildOverview() {
        return MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TodoMobileStatusOverview(
                  counts: const TodoViewCounts(
                    active: 2,
                    overdue: 1,
                    completed: 3,
                  ),
                  selectedFilter: selectedFilter,
                  accentColor: const Color(0xFFC96442),
                  successColor: const Color(0xFF17A34A),
                  onFilterChanged: (filter) {
                    setState(() => selectedFilter = filter);
                  },
                );
              },
            ),
          ),
        );
      }

      await tester.pumpWidget(buildOverview());

      expect(find.text('当前'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('逾期'), findsNothing);
      expect(
        find.byKey(const ValueKey('todo-filter-count-当前')),
        findsOneWidget,
      );
      expect(find.text('1 条任务已逾期'), findsOneWidget);
      expect(find.text('只看逾期'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('todo-mobile-overdue-priority')),
      );
      await tester.pumpAndSettle();

      expect(selectedFilter, TodoViewFilter.overdue);
      expect(find.text('查看全部当前'), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('todo-mobile-status-current-tab')),
            )
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey('todo-mobile-status-completed-tab')),
      );
      await tester.pumpAndSettle();

      expect(selectedFilter, TodoViewFilter.completed);
      expect(
        find.byKey(const ValueKey('todo-mobile-overdue-priority')),
        findsNothing,
      );
    },
  );
}
