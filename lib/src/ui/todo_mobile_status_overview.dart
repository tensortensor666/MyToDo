import 'package:flutter/material.dart';

import 'todo_filter_tab_content.dart';
import 'todo_view_filter.dart';

class TodoMobileStatusOverview extends StatelessWidget {
  const TodoMobileStatusOverview({
    super.key,
    required this.counts,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.accentColor,
    required this.successColor,
  });

  final TodoViewCounts counts;
  final TodoViewFilter selectedFilter;
  final ValueChanged<TodoViewFilter> onFilterChanged;
  final Color accentColor;
  final Color successColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pendingSelected =
        selectedFilter == TodoViewFilter.active ||
        selectedFilter == TodoViewFilter.overdue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Color.lerp(
              scheme.surface,
              scheme.surfaceContainerHighest,
              0.24,
            ),
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: _MobileStatusTab(
                  key: const ValueKey('todo-mobile-status-current-tab'),
                  label: '当前',
                  count: counts.pending,
                  color: scheme.primary,
                  accentColor: accentColor,
                  selected: pendingSelected,
                  onTap: () => onFilterChanged(TodoViewFilter.active),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MobileStatusTab(
                  key: const ValueKey('todo-mobile-status-completed-tab'),
                  label: '完成',
                  count: counts.completed,
                  color: successColor,
                  accentColor: accentColor,
                  selected: selectedFilter == TodoViewFilter.completed,
                  onTap: () => onFilterChanged(TodoViewFilter.completed),
                ),
              ),
            ],
          ),
        ),
        if (selectedFilter != TodoViewFilter.completed &&
            counts.overdue > 0) ...[
          const SizedBox(height: 12),
          _OverduePriorityCard(
            count: counts.overdue,
            selected: selectedFilter == TodoViewFilter.overdue,
            onTap: () => onFilterChanged(
              selectedFilter == TodoViewFilter.overdue
                  ? TodoViewFilter.active
                  : TodoViewFilter.overdue,
            ),
          ),
        ],
      ],
    );
  }
}

class _MobileStatusTab extends StatelessWidget {
  const _MobileStatusTab({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    required this.accentColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final Color accentColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? scheme.surface : Colors.transparent,
              border: Border.all(
                color: selected ? scheme.outlineVariant : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: scheme.onSurface.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: TodoFilterTabContent(
                label: label,
                count: count,
                color: color,
                accentColor: accentColor,
                selected: selected,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverduePriorityCard extends StatelessWidget {
  const _OverduePriorityCard({
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$count 条任务已逾期',
      hint: selected ? '查看全部当前任务' : '只看逾期任务',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('todo-mobile-overdue-priority'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Color.lerp(
                scheme.surface,
                scheme.errorContainer,
                selected ? 0.36 : 0.22,
              ),
              border: Border.all(
                color: scheme.error.withValues(alpha: selected ? 0.48 : 0.24),
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: scheme.error.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.calendar_today_outlined,
                    size: 19,
                    color: scheme.onError,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '优先处理',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$count 条任务已逾期',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已在“当前”中置顶，建议先处理。',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minHeight: 30),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? scheme.error : scheme.surface,
                    border: Border.all(
                      color: scheme.error.withValues(
                        alpha: selected ? 1 : 0.22,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    selected ? '查看全部当前' : '只看逾期',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? scheme.onError : scheme.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
