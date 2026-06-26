import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/data/todo_store.dart';

void main() {
  test('event log can be applied to another local store', () async {
    final first = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(
        deviceId: 'device-a',
        name: 'Device A',
        token: 'token-a',
      ),
    );
    final second = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(
        deviceId: 'device-b',
        name: 'Device B',
        token: 'token-b',
      ),
    );

    await first.createTodo('Buy milk');
    final events = await first.eventsAfterClock(await second.eventClock());
    final applied = await second.applyRemoteEvents(events);

    expect(applied, 1);
    expect(second.todos, hasLength(1));
    expect(second.todos.single.title, 'Buy milk');
    expect(second.todos.single.completed, isFalse);
  });

  test('newer remote event wins for the same todo', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(
        deviceId: 'device-a',
        name: 'Device A',
        token: 'token-a',
      ),
    );

    const older = TodoEvent(
      eventId: 'older',
      deviceId: 'remote',
      seq: 1,
      timestamp: 100,
      type: 'todo.upsert',
      todoId: 'todo-1',
      payload: {
        'id': 'todo-1',
        'title': 'Old title',
        'completed': false,
        'deleted': false,
        'createdAt': 100,
        'updatedAt': 100,
      },
    );
    const newer = TodoEvent(
      eventId: 'newer',
      deviceId: 'remote',
      seq: 2,
      timestamp: 200,
      type: 'todo.upsert',
      todoId: 'todo-1',
      payload: {
        'id': 'todo-1',
        'title': 'New title',
        'completed': true,
        'deleted': false,
        'createdAt': 100,
        'updatedAt': 200,
      },
    );

    await store.applyRemoteEvents([newer, older]);

    expect(store.todos.single.title, 'New title');
    expect(store.todos.single.completed, isTrue);
  });

  test('search includes deleted todo history', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(
        deviceId: 'device-a',
        name: 'Device A',
        token: 'token-a',
      ),
    );

    await store.createTodo('Archive invoice');
    final todo = store.todos.single;
    await store.deleteTodo(todo);

    expect(store.todos, isEmpty);

    final results = store.searchTodos('invoice');
    expect(results, hasLength(1));
    expect(results.single.title, 'Archive invoice');
    expect(results.single.deleted, isTrue);
  });

  test('todo can store due date and reminder time', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(
        deviceId: 'device-a',
        name: 'Device A',
        token: 'token-a',
      ),
    );

    await store.createTodo('Plan launch', dueAt: 2000, reminderAt: 1500);

    expect(store.todos.single.dueAt, 2000);
    expect(store.todos.single.reminderAt, 1500);

    await store.updateTodo(
      store.todos.single,
      title: 'Plan launch',
      dueAt: null,
      reminderAt: 3000,
    );

    expect(store.todos.single.dueAt, isNull);
    expect(store.todos.single.reminderAt, 3000);
  });

  test('deleted todo can be restored', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(
        deviceId: 'device-a',
        name: 'Device A',
        token: 'token-a',
      ),
    );

    await store.createTodo('Restore me');
    final todo = store.todos.single;
    await store.deleteTodo(todo);

    expect(store.todos, isEmpty);

    await store.restoreTodo(store.searchTodos('restore').single);

    expect(store.todos, hasLength(1));
    expect(store.todos.single.title, 'Restore me');
    expect(store.todos.single.deleted, isFalse);
  });
}
