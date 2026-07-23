import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/ui/nav_views.dart';

void main() {
  test('new todo has no default due date from every view', () {
    final now = DateTime(2026, 7, 6, 10, 30);

    expect(defaultDueAtForNewTodoView(TodoList.viewMyDayId, now), isNull);
    expect(defaultDueAtForNewTodoView(TodoList.viewPlannedId, now), isNull);
    expect(defaultDueAtForNewTodoView(TodoList.inboxId, now), isNull);
    expect(defaultDueAtForNewTodoView(TodoList.viewImportantId, now), isNull);
    expect(defaultDueAtForNewTodoView('custom-list', now), isNull);
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
