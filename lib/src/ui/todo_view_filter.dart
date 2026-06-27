import '../data/todo_models.dart';

enum TodoViewFilter { active, overdue, completed }

class TodoViewCounts {
  const TodoViewCounts({
    required this.active,
    required this.overdue,
    required this.completed,
  });

  final int active;
  final int overdue;
  final int completed;
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
        };
      })
      .toList(growable: false);
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
