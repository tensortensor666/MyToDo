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
      sortOrder: 1500,
      listId: TodoList.inboxId,
      templateId: 'template-1',
      taskDate: '2026-06-30',
      sourceType: TodoSource.recurring,
      dueAt: 3000,
      reminderAt: 2500,
      notes: '- buy oat milk\n**urgent**',
    );

    expect(TodoItem.fromJson(todo.toJson()).toJson(), todo.toJson());
    expect(TodoItem.fromDb(todo.toDb()).toJson(), todo.toJson());
  });

  test('todo item defaults sort order for old payloads', () {
    final todo = TodoItem.fromJson(const {
      'id': 'todo-old',
      'title': 'Old payload',
      'completed': false,
      'deleted': false,
      'createdAt': 1234,
      'updatedAt': 2234,
    });

    expect(todo.sortOrder, 1234);
    expect(todo.notes, isEmpty);
    expect(TodoItem.fromDb(todo.toDb()).sortOrder, 1234);
  });

  test('todo item preserves important flag and defaults to false', () {
    const important = TodoItem(
      id: 'todo-2',
      title: 'Pay rent',
      completed: false,
      deleted: false,
      createdAt: 1000,
      updatedAt: 2000,
      important: true,
    );
    const notImportant = TodoItem(
      id: 'todo-3',
      title: 'Sweep floor',
      completed: false,
      deleted: false,
      createdAt: 1000,
      updatedAt: 2000,
    );

    expect(important.important, isTrue);
    expect(notImportant.important, isFalse);
    expect(TodoItem.fromJson(important.toJson()).important, isTrue);
    expect(TodoItem.fromDb(important.toDb()).important, isTrue);
    expect(TodoItem.fromJson(notImportant.toJson()).important, isFalse);
  });

  test('todo list and recurring template round trip through json and db', () {
    const list = TodoList(
      id: 'list-1',
      name: 'Daily',
      sortOrder: 1,
      isSystem: false,
      createdAt: 100,
      updatedAt: 200,
    );
    const template = RecurringTemplate(
      id: 'template-1',
      listId: 'list-1',
      title: 'Brush teeth',
      repeatType: RepeatType.daily,
      startDate: '2026-06-30',
      archived: false,
      createdAt: 100,
      updatedAt: 200,
      notes: '- every morning',
    );

    expect(TodoList.fromJson(list.toJson()).toJson(), list.toJson());
    expect(TodoList.fromDb(list.toDb()).toJson(), list.toJson());

    const colored = TodoList(
      id: 'list-2',
      name: 'Urgent',
      sortOrder: 2,
      isSystem: false,
      createdAt: 100,
      updatedAt: 200,
      color: 0xFFE0463B,
    );
    expect(colored.color, 0xFFE0463B);
    expect(TodoList.fromJson(colored.toJson()).color, 0xFFE0463B);
    expect(TodoList.fromDb(colored.toDb()).color, 0xFFE0463B);
    expect(
      RecurringTemplate.fromJson(template.toJson()).toJson(),
      template.toJson(),
    );
    expect(
      RecurringTemplate.fromDb(template.toDb()).toJson(),
      template.toJson(),
    );
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
