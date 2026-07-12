import 'package:flutter/material.dart';

import '../data/todo_models.dart';
import '../data/todo_store.dart';

class TodoNavEntry {
  const TodoNavEntry({
    required this.id,
    required this.name,
    required this.icon,
    required this.accent,
    this.list,
    this.isCustomList = false,
    this.isSavingsView = false,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color accent;
  final TodoList? list;
  final bool isCustomList;
  final bool isSavingsView;

  bool get isVirtual => list == null;
}

const Color kMsPrimary = Color(0xFFC96442);
const Color kMsImportantStar = Color(0xFFC96442);
const List<Color> kListColorPalette = [
  Color(0xFFC96442),
  Color(0xFF5F7F62),
  Color(0xFFB53333),
  Color(0xFFEAB308),
  Color(0xFF17A34A),
  Color(0xFF3D3D3A),
  Color(0xFF87867F),
  Color(0xFFE8E6DC),
  Color(0xFF141413),
];

Color accentForList(TodoList list) {
  if (list.color != null) {
    return Color(list.color!);
  }
  switch (list.id) {
    case TodoList.inboxId:
      return kMsPrimary;
    default:
      return kMsPrimary;
  }
}

IconData iconForList(TodoList list) {
  switch (list.id) {
    case TodoList.inboxId:
      return Icons.inbox_outlined;
    default:
      return Icons.list_alt;
  }
}

List<TodoNavEntry> buildNavEntries(TodoStore store) {
  return [
    TodoNavEntry(
      id: TodoList.viewMyDayId,
      name: '我的一天',
      icon: Icons.wb_sunny_outlined,
      accent: kMsPrimary,
    ),
    TodoNavEntry(
      id: TodoList.viewImportantId,
      name: '重要',
      icon: Icons.star_rounded,
      accent: kMsImportantStar,
    ),
    TodoNavEntry(
      id: TodoList.viewPlannedId,
      name: '已计划',
      icon: Icons.event_outlined,
      accent: kMsPrimary,
    ),
    for (final list in store.lists)
      TodoNavEntry(
        id: list.id,
        name: list.name,
        icon: iconForList(list),
        accent: accentForList(list),
        list: list,
        isCustomList: !list.isSystem,
      ),
    TodoNavEntry(
      id: TodoList.viewSavingsId,
      name: '存钱清单',
      icon: Icons.savings_outlined,
      accent: kMsPrimary,
      isSavingsView: true,
    ),
  ];
}

String subtitleForView(String id) {
  switch (id) {
    case TodoList.viewMyDayId:
      return '聚焦今天能推动结果的任务，其余内容留在清单里。';
    case TodoList.viewImportantId:
      return '标记为重要的任务';
    case TodoList.viewPlannedId:
      return '按截止日期排序';
    case TodoList.viewSavingsId:
      return '把目标拆成一个个存钱计划，每次存一笔就推进一点点进度。';
    default:
      return '';
  }
}

int? defaultDueAtForNewTodoView(String selectedListId, DateTime now) {
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

String targetListIdForNewTodoView(String selectedListId) {
  return switch (selectedListId) {
    TodoList.viewMyDayId => TodoList.inboxId,
    TodoList.viewImportantId => TodoList.inboxId,
    TodoList.viewPlannedId => TodoList.inboxId,
    _ => selectedListId,
  };
}

bool defaultImportantForNewTodoView(String selectedListId) {
  return selectedListId == TodoList.viewImportantId;
}
