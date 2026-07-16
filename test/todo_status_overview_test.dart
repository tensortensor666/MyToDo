import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/ui/todo_status_overview.dart';
import 'package:mytodo/src/ui/todo_view_filter.dart';

void main() {
  for (final compact in [true, false]) {
    testWidgets(
      '${compact ? 'mobile' : 'desktop'} overview keeps overdue inside current',
      (tester) async {
        var selectedFilter = TodoViewFilter.active;

        Widget buildOverview() {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: compact ? 380 : 700,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      return TodoStatusOverview(
                        counts: const TodoViewCounts(
                          active: 2,
                          overdue: 1,
                          completed: 3,
                        ),
                        selectedFilter: selectedFilter,
                        accentColor: const Color(0xFFC96442),
                        successColor: const Color(0xFF17A34A),
                        compact: compact,
                        onFilterChanged: (filter) {
                          setState(() => selectedFilter = filter);
                        },
                      );
                    },
                  ),
                ),
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

        await tester.tap(find.byKey(const ValueKey('todo-overdue-priority')));
        await tester.pumpAndSettle();

        expect(selectedFilter, TodoViewFilter.overdue);
        expect(find.text('查看全部当前'), findsOneWidget);
        expect(
          tester
              .getSemantics(
                find.byKey(const ValueKey('todo-status-current-tab')),
              )
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );

        await tester.tap(
          find.byKey(const ValueKey('todo-status-completed-tab')),
        );
        await tester.pumpAndSettle();

        expect(selectedFilter, TodoViewFilter.completed);
        expect(
          find.byKey(const ValueKey('todo-overdue-priority')),
          findsNothing,
        );
      },
    );
  }
}
