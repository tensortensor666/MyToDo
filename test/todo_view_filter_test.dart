import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/ui/todo_view_filter.dart';

void main() {
  test('todo view filter separates current overdue and completed todos', () {
    const now = 1000;
    const todos = [
      TodoItem(
        id: 'current',
        title: 'Current task',
        completed: false,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
        dueAt: 1200,
      ),
      TodoItem(
        id: 'overdue',
        title: 'Overdue task',
        completed: false,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
        dueAt: 800,
      ),
      TodoItem(
        id: 'completed',
        title: 'Completed task',
        completed: true,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
        dueAt: 800,
      ),
    ];

    expect(
      filterTodosByView(
        todos,
        TodoViewFilter.active,
        now,
      ).map((todo) => todo.id),
      ['current'],
    );
    expect(
      filterTodosByView(
        todos,
        TodoViewFilter.overdue,
        now,
      ).map((todo) => todo.id),
      ['overdue'],
    );
    expect(
      filterTodosByView(
        todos,
        TodoViewFilter.completed,
        now,
      ).map((todo) => todo.id),
      ['completed'],
    );
    expect(
      filterTodosByView(todos, TodoViewFilter.all, now).map((todo) => todo.id),
      ['current', 'overdue', 'completed'],
    );
  });

  test('todo view counts match exclusive view filters', () {
    const now = 1000;
    const todos = [
      TodoItem(
        id: 'current',
        title: 'Current task',
        completed: false,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
      ),
      TodoItem(
        id: 'overdue',
        title: 'Overdue task',
        completed: false,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
        dueAt: 800,
      ),
      TodoItem(
        id: 'completed',
        title: 'Completed task',
        completed: true,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
      ),
    ];

    final counts = countTodosByView(todos, now);

    expect(counts.active, 1);
    expect(counts.overdue, 1);
    expect(counts.completed, 1);
    expect(counts.pending, 2);
  });

  test('compact current includes overdue tasks and prioritizes them', () {
    const now = 1000;
    const todos = [
      TodoItem(
        id: 'current-1',
        title: 'Current one',
        completed: false,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
      ),
      TodoItem(
        id: 'overdue-1',
        title: 'Overdue one',
        completed: false,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
        dueAt: 800,
      ),
      TodoItem(
        id: 'current-2',
        title: 'Current two',
        completed: false,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
      ),
      TodoItem(
        id: 'overdue-2',
        title: 'Overdue two',
        completed: false,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
        dueAt: 900,
      ),
      TodoItem(
        id: 'completed',
        title: 'Completed',
        completed: true,
        deleted: false,
        createdAt: 100,
        updatedAt: 100,
      ),
    ];

    expect(
      filterTodosByCompactView(
        todos,
        TodoViewFilter.active,
        now,
      ).map((todo) => todo.id),
      ['overdue-1', 'overdue-2', 'current-1', 'current-2'],
    );
    expect(
      filterTodosByCompactView(
        todos,
        TodoViewFilter.completed,
        now,
      ).map((todo) => todo.id),
      ['completed'],
    );
  });
}
