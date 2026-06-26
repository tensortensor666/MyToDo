import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';

void main() {
  test('todo item round trips through json and database maps', () {
    const todo = TodoItem(
      id: 'todo-1',
      title: 'Buy milk',
      completed: false,
      deleted: false,
      createdAt: 1000,
      updatedAt: 2000,
      dueAt: 3000,
      reminderAt: 2500,
    );

    expect(TodoItem.fromJson(todo.toJson()).toJson(), todo.toJson());
    expect(TodoItem.fromDb(todo.toDb()).toJson(), todo.toJson());
  });

  test('todo event round trips through json and database maps', () {
    const event = TodoEvent(
      eventId: 'event-1',
      deviceId: 'device-1',
      seq: 1,
      timestamp: 2000,
      type: 'todo.upsert',
      todoId: 'todo-1',
      payload: {'id': 'todo-1', 'title': 'Buy milk'},
    );

    expect(TodoEvent.fromJson(event.toJson()).toJson(), event.toJson());
    expect(TodoEvent.fromDb(event.toDb()).toJson(), event.toJson());
  });
}
