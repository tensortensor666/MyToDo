import 'package:flutter/material.dart';

const todoDeleteUndoDuration = Duration(seconds: 4);

SnackBar buildTodoDeleteUndoSnackBar({
  required String title,
  required VoidCallback onUndo,
}) {
  return SnackBar(
    duration: todoDeleteUndoDuration,
    persist: false,
    content: Text('已删除“$title”'),
    action: SnackBarAction(label: '撤销', onPressed: onUndo),
  );
}

class TodoEditorDeleteSection extends StatelessWidget {
  const TodoEditorDeleteSection({
    super.key,
    required this.titleController,
    required this.fallbackTitle,
    required this.onConfirmed,
  });

  final TextEditingController titleController;
  final String fallbackTitle;
  final Future<void> Function(String title) onConfirmed;

  Future<void> _requestDelete(BuildContext context) async {
    final trimmedTitle = titleController.text.trim();
    final deleteTitle = trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle;
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmationContext) {
        return AlertDialog(
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '确认删除',
                      style: Theme.of(confirmationContext).textTheme.labelMedium
                          ?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text('删除这条任务？'),
                  ],
                ),
              ),
              IconButton(
                tooltip: '取消删除',
                onPressed: () => Navigator.of(confirmationContext).pop(false),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          content: Text('“$deleteTitle”将从当前清单移除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmationContext).pop(false),
              child: const Text('保留任务'),
            ),
            FilledButton.icon(
              key: const ValueKey('confirm-delete-todo'),
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.of(confirmationContext).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('确认删除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await onConfirmed(deleteTitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.05),
        border: Border.all(color: scheme.error.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '危险操作',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '删除这条任务',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '删除后会返回任务列表，并提供一次撤销机会。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('delete-todo-from-editor'),
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => _requestDelete(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除任务'),
          ),
        ],
      ),
    );
  }
}
