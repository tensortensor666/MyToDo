import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/todo_store.dart';

class TodoWidgetTask {
  const TodoWidgetTask({
    required this.id,
    required this.title,
    required this.listName,
    required this.important,
    required this.dueAt,
  });

  final String id;
  final String title;
  final String listName;
  final bool important;
  final int? dueAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'listName': listName,
    'important': important,
    'dueAt': dueAt,
  };
}

class TodoWidgetSnapshot {
  const TodoWidgetSnapshot({required this.activeCount, required this.tasks});

  final int activeCount;
  final List<TodoWidgetTask> tasks;

  Map<String, Object?> toJson() => {
    'activeCount': activeCount,
    'tasks': tasks.map((task) => task.toJson()).toList(growable: false),
  };
}

class TodoWidgetService {
  TodoWidgetService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.tensortensor666.mytodo/home_widget';
  static const maxVisibleTasks = 5;

  final MethodChannel _channel;

  @visibleForTesting
  static TodoWidgetSnapshot buildSnapshot(TodoStore store) {
    final activeTodos = store.todos
        .where((todo) => !todo.completed && !todo.deleted)
        .toList(growable: false);
    final tasks = activeTodos
        .take(maxVisibleTasks)
        .map((todo) {
          final list = store.listById(todo.listId);
          return TodoWidgetTask(
            id: todo.id,
            title: todo.title,
            listName: list?.name ?? '收件箱',
            important: todo.important,
            dueAt: todo.dueAt,
          );
        })
        .toList(growable: false);
    return TodoWidgetSnapshot(activeCount: activeTodos.length, tasks: tasks);
  }

  Future<void> update(TodoStore store) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final payload = jsonEncode(buildSnapshot(store).toJson());
    try {
      await _channel.invokeMethod<void>('updateWidget', payload);
    } on PlatformException catch (error) {
      debugPrint('Unable to update Android home widget: $error');
    } on MissingPluginException {
      // The widget bridge is unavailable in tests and on older installations.
    }
  }

  Future<bool> requestPin() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('requestPinWidget') ?? false;
    } on PlatformException catch (error) {
      debugPrint('Unable to request Android widget pin: $error');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
