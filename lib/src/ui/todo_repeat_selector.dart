import 'package:flutter/material.dart';

enum TodoRepeatOption { none, daily }

class TodoRepeatSelector extends StatelessWidget {
  const TodoRepeatSelector({
    super.key,
    required this.value,
    required this.startedAsDaily,
    required this.accentColor,
    required this.warningColor,
    required this.onChanged,
  });

  final TodoRepeatOption value;
  final bool startedAsDaily;
  final Color accentColor;
  final Color warningColor;
  final ValueChanged<TodoRepeatOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cancelling = startedAsDaily && value == TodoRepeatOption.none;
    final daily = value == TodoRepeatOption.daily;
    final summaryColor = cancelling ? warningColor : accentColor;
    final summaryTitle = cancelling
        ? '将取消每天重复'
        : daily
        ? '每天重复'
        : '仅此一次';
    final summaryDescription = cancelling
        ? '保存后停止生成后续任务，当前这条任务仍会保留。'
        : daily
        ? '每天自动生成一条新任务。'
        : '任务只保留一次，不会自动生成。';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TodoRepeatOption>(
          key: const ValueKey('todo-repeat-selector'),
          segments: const [
            ButtonSegment(
              value: TodoRepeatOption.none,
              icon: Icon(Icons.check_circle_outline),
              label: Text('不重复'),
            ),
            ButtonSegment(
              value: TodoRepeatOption.daily,
              icon: Icon(Icons.repeat),
              label: Text('每天'),
            ),
          ],
          selected: {value},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.single),
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? accentColor
                  : scheme.onSurfaceVariant;
            }),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: AnimatedContainer(
            key: const ValueKey('todo-repeat-summary'),
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.lerp(scheme.surface, summaryColor, 0.09),
              border: Border.all(color: summaryColor.withValues(alpha: 0.32)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: summaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.repeat, size: 19, color: scheme.onPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summaryTitle,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summaryDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
