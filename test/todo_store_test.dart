import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/data/todo_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<TodoStore> _freshStore(String deviceId) {
  return TodoStore.openInMemoryForTesting(
    device: LocalDevice(deviceId: deviceId, name: deviceId),
  );
}

int _endOfTodayMs() {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    23,
    59,
    59,
    999,
  ).millisecondsSinceEpoch;
}

void main() {
  test('event log can be applied to another local store', () async {
    final first = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
    );
    final second = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-b', name: 'Device B'),
    );

    await first.createTodo('Buy milk', notes: '- use Markdown');
    final events = await first.eventsAfterClock(await second.eventClock());
    final applied = await second.applyRemoteEvents(events);

    expect(applied, 1);
    expect(second.todos, hasLength(1));
    expect(second.todos.single.title, 'Buy milk');
    expect(second.todos.single.notes, '- use Markdown');
    expect(second.todos.single.completed, isFalse);
  });

  test('event log syncs custom lists and recurring templates', () async {
    final first = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
    );
    final second = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-b', name: 'Device B'),
    );

    final life = await first.createTodoList('Life');
    await first.createRecurringTemplate('Brush teeth', listId: life.id);

    final events = await first.eventsAfterClock(await second.eventClock());
    final applied = await second.applyRemoteEvents(events);
    await second.ensureDailyRecurringTodos();

    expect(applied, 2);
    expect(second.listById(life.id)?.name, 'Life');
    expect(second.recurringTemplates.single.title, 'Brush teeth');
    expect(second.visibleTodosForList(life.id).single.title, 'Brush teeth');
  });

  test('newer remote event wins for the same todo', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
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
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
    );

    await store.createTodo('Archive invoice', notes: 'Receipt #2026');
    final todo = store.todos.single;
    await store.deleteTodo(todo);

    expect(store.todos, isEmpty);

    final results = store.searchTodos('invoice');
    expect(results, hasLength(1));
    expect(results.single.title, 'Archive invoice');
    expect(results.single.deleted, isTrue);

    final noteResults = store.searchTodos('receipt');
    expect(noteResults, hasLength(1));
    expect(noteResults.single.notes, 'Receipt #2026');
  });

  test('todo notes can be created updated searched and synced', () async {
    final first = await _freshStore('device-a');
    final second = await _freshStore('device-b');

    await first.createTodo('Research sync', notes: '- draft\n**important**');

    expect(first.todos.single.notes, '- draft\n**important**');
    expect(first.searchTodos('important').single.title, 'Research sync');

    await first.updateTodo(
      first.todos.single,
      title: 'Research sync',
      listId: first.todos.single.listId,
      dueAt: first.todos.single.dueAt,
      reminderAt: first.todos.single.reminderAt,
      notes: '## Plan\n- confirm API',
    );

    expect(first.todos.single.notes, '## Plan\n- confirm API');

    final events = await first.eventsAfterClock(await second.eventClock());
    await second.applyRemoteEvents(events);

    expect(second.todos.single.notes, '## Plan\n- confirm API');
    expect(second.searchTodos('confirm API'), hasLength(1));
  });

  test('todos can be manually reordered and synced', () async {
    final first = await _freshStore('device-a');
    final second = await _freshStore('device-b');

    await first.createTodo('Alpha');
    await first.createTodo('Bravo');
    await first.createTodo('Charlie');

    expect(
      first.visibleTodosForList(TodoList.inboxId).map((todo) => todo.title),
      ['Alpha', 'Bravo', 'Charlie'],
    );

    await first.reorderTodos([first.todos[2], first.todos[0], first.todos[1]]);

    expect(
      first.visibleTodosForList(TodoList.inboxId).map((todo) => todo.title),
      ['Charlie', 'Alpha', 'Bravo'],
    );

    final events = await first.eventsAfterClock(await second.eventClock());
    await second.applyRemoteEvents(events);

    expect(
      second.visibleTodosForList(TodoList.inboxId).map((todo) => todo.title),
      ['Charlie', 'Alpha', 'Bravo'],
    );
  });

  test('todo can store due date and reminder time', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
    );

    await store.createTodo('Plan launch', dueAt: 2000, reminderAt: 1500);

    expect(store.todos.single.dueAt, 2000);
    expect(store.todos.single.reminderAt, 1500);

    await store.updateTodo(
      store.todos.single,
      title: 'Plan launch',
      listId: store.todos.single.listId,
      dueAt: null,
      reminderAt: 3000,
    );

    expect(store.todos.single.dueAt, isNull);
    expect(store.todos.single.reminderAt, 3000);
  });

  test('todo can move to another list and append to target list', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
    );

    final work = await store.createTodoList('Work');
    final life = await store.createTodoList('Life');
    await store.createTodo('Move me', listId: work.id);
    await store.createTodo('Existing life item', listId: life.id);

    final movingTodo = store.todos.firstWhere(
      (todo) => todo.title == 'Move me',
    );
    final existingTodo = store.todos.firstWhere(
      (todo) => todo.title == 'Existing life item',
    );

    await store.updateTodo(
      movingTodo,
      title: movingTodo.title,
      listId: life.id,
      dueAt: movingTodo.dueAt,
      reminderAt: movingTodo.reminderAt,
    );

    expect(store.visibleTodosForList(work.id), isEmpty);
    expect(store.visibleTodosForList(life.id).map((todo) => todo.title), [
      'Existing life item',
      'Move me',
    ]);
    expect(
      store.todos.firstWhere((todo) => todo.title == 'Move me').sortOrder,
      greaterThan(existingTodo.sortOrder),
    );
  });

  test('deleted todo can be restored', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
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

  test('store seeds system lists and filters todos by list', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
    );

    expect(store.lists.map((list) => list.id), contains(TodoList.inboxId));
    expect(
      store.lists.map((list) => list.id),
      isNot(contains(TodoList.dailyId)),
    );

    final work = await store.createTodoList('Work');
    await store.createTodo('Inbox item');
    await store.createTodo('Work item', listId: work.id);

    expect(store.visibleTodosForList(TodoList.inboxId), hasLength(2));
    expect(store.visibleTodosForList(work.id).map((todo) => todo.title), [
      'Work item',
    ]);
  });

  test('daily recurring template generates at most one todo per day', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
    );

    await store.createRecurringTemplate(
      'Brush teeth',
      listId: TodoList.inboxId,
      notes: '- morning routine',
    );
    final firstCount = store.visibleTodosForList(TodoList.inboxId).length;

    await store.ensureDailyRecurringTodos();
    final secondCount = store.visibleTodosForList(TodoList.inboxId).length;

    expect(firstCount, 1);
    expect(secondCount, 1);
    expect(
      store.visibleTodosForList(TodoList.inboxId).single.sourceType,
      TodoSource.recurring,
    );
    expect(
      store.visibleTodosForList(TodoList.inboxId).single.notes,
      '- morning routine',
    );
  });

  test('deleting custom list moves todos and templates into inbox', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
    );

    final life = await store.createTodoList('Life');
    await store.createTodo('Stretch', listId: life.id);
    await store.createRecurringTemplate('Run', listId: life.id);

    await store.deleteTodoList(life);

    expect(store.listById(life.id), isNull);
    expect(
      store.todos.every((todo) => todo.listId == TodoList.inboxId),
      isTrue,
    );
    expect(
      store.recurringTemplates.every(
        (template) => template.listId == TodoList.inboxId,
      ),
      isTrue,
    );
  });

  test('store can repair a partially upgraded v2 database', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath = p.join(
      Directory.systemTemp.path,
      'mytodo-partial-upgrade-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 2, singleInstance: false),
    );
    addTearDown(() async {
      await databaseFactory.deleteDatabase(dbPath);
    });

    await db.execute('''
CREATE TABLE todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  completed INTEGER NOT NULL,
  deleted INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  due_at INTEGER,
  reminder_at INTEGER
)
''');
    await db.execute('''
CREATE TABLE events (
  event_id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  type TEXT NOT NULL,
  todo_id TEXT NOT NULL,
  payload_json TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE todo_lists (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  is_system INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    await db.setVersion(2);
    await db.close();

    final store = await TodoStore.openPathForTesting(
      dbPath: dbPath,
      device: const LocalDevice(deviceId: 'device-a', name: 'Device A'),
    );

    expect(store.lists.map((list) => list.id), contains(TodoList.inboxId));
    expect(
      store.lists.map((list) => list.id),
      isNot(contains(TodoList.dailyId)),
    );
    await expectLater(
      store.createRecurringTemplate('Brush teeth', listId: TodoList.inboxId),
      completes,
    );
  });

  test(
    'legacy daily system list is removed and synced todos move to inbox',
    () async {
      final store = await _freshStore('device-a');

      final legacyList = TodoList(
        id: TodoList.dailyId,
        name: '生活日常',
        sortOrder: 1,
        isSystem: true,
        createdAt: 100,
        updatedAt: 100,
      );
      final legacyTodo = TodoItem(
        id: 'legacy-todo',
        title: 'Legacy daily task',
        completed: false,
        deleted: false,
        createdAt: 200,
        updatedAt: 200,
        listId: TodoList.dailyId,
      );

      await store.applyRemoteEvents([
        TodoEvent(
          eventId: 'legacy-list',
          deviceId: 'old-device',
          seq: 1,
          timestamp: 100,
          type: 'list.upsert',
          todoId: TodoList.dailyId,
          payload: legacyList.toJson(),
        ),
        TodoEvent(
          eventId: 'legacy-todo',
          deviceId: 'old-device',
          seq: 2,
          timestamp: 200,
          type: 'todo.upsert',
          todoId: legacyTodo.id,
          payload: legacyTodo.toJson(),
        ),
      ]);

      expect(
        store.lists.map((list) => list.id),
        isNot(contains(TodoList.dailyId)),
      );
      expect(store.todos.single.listId, TodoList.inboxId);
      expect(
        store.visibleTodosForList(TodoList.inboxId).single.title,
        'Legacy daily task',
      );
    },
  );

  test('important flag persists and syncs between stores', () async {
    final first = await _freshStore('device-a');
    final second = await _freshStore('device-b');

    await first.createTodo('Pay rent', important: true);
    final todo = first.todos.single;
    expect(todo.important, isTrue);

    await first.setImportant(todo, false);
    expect(first.todos.single.important, isFalse);

    await first.setImportant(first.todos.single, true);

    final events = await first.eventsAfterClock(await second.eventClock());
    await second.applyRemoteEvents(events);

    expect(second.todos.single.important, isTrue);
  });

  test('important view only shows important todos', () async {
    final store = await _freshStore('device-a');
    await store.createTodo('Normal');
    await store.createTodo('Critical', important: true);

    final important = store.visibleTodosForList(TodoList.viewImportantId);
    expect(important.map((todo) => todo.title), ['Critical']);
    expect(store.activeCountFor(TodoList.viewImportantId), 1);
  });

  test(
    'planned view shows only tasks with a due date sorted ascending',
    () async {
      final store = await _freshStore('device-a');
      await store.createTodo('No due');
      await store.createTodo('Later', dueAt: 5000);
      await store.createTodo('Sooner', dueAt: 3000);

      final planned = store.visibleTodosForList(TodoList.viewPlannedId);
      expect(planned.map((todo) => todo.title), ['Sooner', 'Later']);
    },
  );

  test(
    'my day view shows tasks due today and recurring tasks for today',
    () async {
      final store = await _freshStore('device-a');
      await store.createRecurringTemplate(
        'Daily chore',
        listId: TodoList.inboxId,
      );
      await store.createTodo('Due today', dueAt: _endOfTodayMs());
      await store.createTodo('Due tomorrow', dueAt: _endOfTodayMs() + 86400000);

      final myDay = store.visibleTodosForList(TodoList.viewMyDayId);
      expect(
        myDay.map((todo) => todo.title),
        containsAll(['Daily chore', 'Due today']),
      );
      expect(myDay.any((todo) => todo.title == 'Due tomorrow'), isFalse);
    },
  );

  test('list color persists and syncs between stores', () async {
    final first = await _freshStore('device-a');
    final second = await _freshStore('device-b');

    const colorValue = 0xFFE0463B;
    final list = await first.createTodoList('Urgent', color: colorValue);
    expect(list.color, colorValue);
    expect(first.listById(list.id)?.color, colorValue);

    await first.setListColor(list, 0xFF3FA864);
    expect(first.listById(list.id)?.color, 0xFF3FA864);

    final events = await first.eventsAfterClock(await second.eventClock());
    await second.applyRemoteEvents(events);

    expect(second.listById(list.id)?.color, 0xFF3FA864);
  });
}
