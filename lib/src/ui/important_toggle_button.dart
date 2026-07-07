import 'package:flutter/material.dart';

class ImportantToggleButton extends StatelessWidget {
  const ImportantToggleButton({
    super.key,
    required this.important,
    required this.onPressed,
  });

  final bool important;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = important
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: important ? '取消重要' : '标记为重要',
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        color: color,
        selectedIcon: const Icon(Icons.star_rounded),
        icon: const Icon(Icons.star_border_rounded),
        isSelected: important,
        onPressed: onPressed,
      ),
    );
  }
}
