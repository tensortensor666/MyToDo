import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/ui/nav_views.dart';

void main() {
  test('new todo in my day and planned views defaults to the end of today', () {
    final now = DateTime(2026, 7, 6, 10, 30);

    final expected = DateTime(
      2026,
      7,
      6,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;
    expect(defaultDueAtForNewTodoView(TodoList.viewMyDayId, now), expected);
    expect(defaultDueAtForNewTodoView(TodoList.viewPlannedId, now), expected);
  });

  test('new todo outside date-based views has no default due date', () {
    final now = DateTime(2026, 7, 6, 10, 30);

    expect(defaultDueAtForNewTodoView(TodoList.inboxId, now), isNull);
    expect(defaultDueAtForNewTodoView(TodoList.viewImportantId, now), isNull);
  });

  test(
    'virtual views create todos in inbox while custom lists keep their id',
    () {
      expect(
        targetListIdForNewTodoView(TodoList.viewMyDayId),
        TodoList.inboxId,
      );
      expect(
        targetListIdForNewTodoView(TodoList.viewImportantId),
        TodoList.inboxId,
      );
      expect(
        targetListIdForNewTodoView(TodoList.viewPlannedId),
        TodoList.inboxId,
      );
      expect(targetListIdForNewTodoView('custom-list'), 'custom-list');
    },
  );

  test('only important view defaults new todos to important', () {
    expect(defaultImportantForNewTodoView(TodoList.viewImportantId), isTrue);
    expect(defaultImportantForNewTodoView(TodoList.viewMyDayId), isFalse);
    expect(defaultImportantForNewTodoView(TodoList.viewPlannedId), isFalse);
    expect(defaultImportantForNewTodoView(TodoList.inboxId), isFalse);
  });
}
