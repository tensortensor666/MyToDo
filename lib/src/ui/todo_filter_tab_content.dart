import 'package:flutter/material.dart';

class TodoFilterTabContent extends StatelessWidget {
  const TodoFilterTabContent({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    required this.accentColor,
    required this.selected,
  });

  final String label;
  final int count;
  final Color color;
  final Color accentColor;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final badgeBackground = selected
        ? accentColor
        : scheme.surfaceContainerHighest;
    final badgeForeground = selected
        ? scheme.onPrimary
        : scheme.onSurfaceVariant;
    final badgeBorder = selected ? accentColor : scheme.outlineVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          label: '$label任务数量：$count',
          excludeSemantics: true,
          child: AnimatedContainer(
            key: ValueKey('todo-filter-count-$label'),
            duration: const Duration(milliseconds: 160),
            height: 22,
            constraints: const BoxConstraints(minWidth: 22),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeBackground,
              border: Border.all(color: badgeBorder),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              count.toString(),
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: badgeForeground,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
