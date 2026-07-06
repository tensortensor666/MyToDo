import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/ui/nav_views.dart';

void main() {
  test('new todo in my day defaults to the end of today', () {
    final now = DateTime(2026, 7, 6, 10, 30);

    final dueAt = defaultDueAtForNewTodoView(TodoList.viewMyDayId, now);

    expect(dueAt, DateTime(2026, 7, 6, 23, 59, 59, 999).millisecondsSinceEpoch);
  });

  test('new todo outside my day has no default due date', () {
    final now = DateTime(2026, 7, 6, 10, 30);

    expect(defaultDueAtForNewTodoView(TodoList.inboxId, now), isNull);
    expect(defaultDueAtForNewTodoView(TodoList.viewImportantId, now), isNull);
    expect(defaultDueAtForNewTodoView(TodoList.viewPlannedId, now), isNull);
  });
}
