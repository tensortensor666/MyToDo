import '../data/todo_models.dart';

enum TodoViewFilter { active, overdue, completed, all }

class TodoViewCounts {
  const TodoViewCounts({
    required this.active,
    required this.overdue,
    required this.completed,
  });

  final int active;
  final int overdue;
  final int completed;

  int get pending => active + overdue;
}

List<TodoItem> filterTodosByView(
  List<TodoItem> todos,
  TodoViewFilter filter,
  int now,
) {
  return todos
      .where((todo) {
        return switch (filter) {
          TodoViewFilter.active => !todo.completed && !isTodoOverdue(todo, now),
          TodoViewFilter.overdue => !todo.completed && isTodoOverdue(todo, now),
          TodoViewFilter.completed => todo.completed,
          TodoViewFilter.all => true,
        };
      })
      .toList(growable: false);
}

List<TodoItem> filterTodosByCompactView(
  List<TodoItem> todos,
  TodoViewFilter filter,
  int now,
) {
  if (filter != TodoViewFilter.active) {
    return filterTodosByView(todos, filter, now);
  }
  final overdue = <TodoItem>[];
  final current = <TodoItem>[];
  for (final todo in todos) {
    if (todo.completed) {
      continue;
    }
    if (isTodoOverdue(todo, now)) {
      overdue.add(todo);
    } else {
      current.add(todo);
    }
  }
  return [...overdue, ...current];
}

TodoViewCounts countTodosByView(List<TodoItem> todos, int now) {
  var active = 0;
  var overdue = 0;
  var completed = 0;
  for (final todo in todos) {
    if (todo.completed) {
      completed++;
    } else if (isTodoOverdue(todo, now)) {
      overdue++;
    } else {
      active++;
    }
  }
  return TodoViewCounts(active: active, overdue: overdue, completed: completed);
}

bool isTodoOverdue(TodoItem todo, int now) {
  return todo.dueAt != null && todo.dueAt! < now;
}
