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
  });

  final String id;
  final String name;
  final IconData icon;
  final Color accent;
  final TodoList? list;
  final bool isCustomList;

  bool get isVirtual => list == null;
}

const Color kMsPrimary = Color(0xFF4B6EAF);
const Color kMsImportantStar = Color(0xFF4B6EAF);
const Color kMsDailyAccent = Color(0xFF8E6FCB);

const List<Color> kListColorPalette = [
  Color(0xFF4B6EAF),
  Color(0xFFE0463B),
  Color(0xFFF08A24),
  Color(0xFFE2B53A),
  Color(0xFF3FA864),
  Color(0xFF1FA8A0),
  Color(0xFF8E6FCB),
  Color(0xFFD36BA8),
  Color(0xFF6B7280),
];

Color accentForList(TodoList list) {
  if (list.color != null) {
    return Color(list.color!);
  }
  switch (list.id) {
    case TodoList.inboxId:
      return kMsPrimary;
    case TodoList.dailyId:
      return kMsDailyAccent;
    default:
      return kMsPrimary;
  }
}

IconData iconForList(TodoList list) {
  switch (list.id) {
    case TodoList.inboxId:
      return Icons.home_outlined;
    case TodoList.dailyId:
      return Icons.self_improvement;
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
  ];
}

String subtitleForView(String id) {
  switch (id) {
    case TodoList.viewMyDayId:
      return '今天需要完成的事项';
    case TodoList.viewImportantId:
      return '标记为重要的任务';
    case TodoList.viewPlannedId:
      return '按截止日期排序';
    case TodoList.dailyId:
      return '每日自动生成';
    default:
      return '';
  }
}
