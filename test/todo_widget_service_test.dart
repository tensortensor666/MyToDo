import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/data/todo_store.dart';
import 'package:mytodo/src/widget/todo_widget_service.dart';

void main() {
  test(
    'widget snapshot keeps global task order and limits visible tasks',
    () async {
      final store = await TodoStore.openInMemoryForTesting(
        device: const LocalDevice(deviceId: 'widget-device', name: 'Widget'),
      );
      final work = await store.createTodoList('工作');
      final life = await store.createTodoList('生活');

      await store.createTodo('任务 1', listId: work.id, important: true);
      await store.createTodo('任务 2', listId: life.id);
      await store.createTodo('任务 3');
      await store.createTodo('任务 4', listId: work.id);
      await store.createTodo('任务 5', listId: life.id);
      await store.createTodo('任务 6');
      await store.createTodo('已完成任务');
      final completed = store.todos.singleWhere(
        (todo) => todo.title == '已完成任务',
      );
      await store.setCompleted(completed, true);

      final snapshot = TodoWidgetService.buildSnapshot(store);

      expect(snapshot.activeCount, 6);
      expect(snapshot.tasks.map((task) => task.title), [
        '任务 1',
        '任务 2',
        '任务 3',
        '任务 4',
        '任务 5',
      ]);
      expect(snapshot.tasks.map((task) => task.listName), [
        '工作',
        '生活',
        '收件箱',
        '工作',
        '生活',
      ]);
      expect(snapshot.tasks.first.important, isTrue);
    },
  );
}
