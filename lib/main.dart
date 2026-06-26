import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'src/app_controller.dart';
import 'src/data/todo_models.dart';
import 'src/desktop/windows_tray.dart';
import 'src/update/update_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeWindowsWindow();
  runApp(const MyTodoApp());
}

class MyTodoApp extends StatelessWidget {
  const MyTodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MyTodo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F7A6D),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const AppBootstrap(),
    );
  }
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<AppController> _future = AppController.create();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppController>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('启动失败: ${snapshot.error}'),
              ),
            ),
          );
        }
        final controller = snapshot.data;
        if (controller == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return TodoHome(controller: controller);
      },
    );
  }
}

class TodoHome extends StatefulWidget {
  const TodoHome({super.key, required this.controller});

  final AppController controller;

  @override
  State<TodoHome> createState() => _TodoHomeState();
}

class _TodoHomeState extends State<TodoHome> {
  WindowsTrayController? _windowsTrayController;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _windowsTrayController = WindowsTrayController(widget.controller);
      unawaited(_windowsTrayController!.initialize());
    }
  }

  @override
  void dispose() {
    _windowsTrayController?.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            const _AddTodoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const _SearchTodosIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            const _SyncTodosIntent(),
      },
      child: Actions(
        actions: {
          _AddTodoIntent: CallbackAction<_AddTodoIntent>(
            onInvoke: (_) {
              _showAddTodoDialog();
              return null;
            },
          ),
          _SearchTodosIntent: CallbackAction<_SearchTodosIntent>(
            onInvoke: (_) {
              _openHistorySearch();
              return null;
            },
          ),
          _SyncTodosIntent: CallbackAction<_SyncTodosIntent>(
            onInvoke: (_) {
              widget.controller.sync.syncAllTrustedDevices();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('MyTodo'),
                  actions: [
                    IconButton(
                      tooltip: '搜索历史',
                      onPressed: _openHistorySearch,
                      icon: const Icon(Icons.search),
                    ),
                    IconButton(
                      tooltip: '检查更新',
                      onPressed: _openUpdatePage,
                      icon: const Icon(Icons.system_update),
                    ),
                    IconButton(
                      tooltip: '同步和设备',
                      onPressed: _openSyncPage,
                      icon: const Icon(Icons.devices),
                    ),
                  ],
                ),
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _TodoPanel(
                        controller: widget.controller,
                        scrollTodos: true,
                        onAddTodo: _showAddTodoDialog,
                      ),
                    ),
                  ),
                ),
                floatingActionButton: FloatingActionButton.extended(
                  onPressed: _showAddTodoDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('添加任务'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openHistorySearch() async {
    await showSearch<void>(
      context: context,
      delegate: _TodoHistorySearchDelegate(controller: widget.controller),
    );
  }

  Future<void> _showAddTodoDialog() async {
    await _showTodoEditorDialog(
      context,
      controller: widget.controller,
      title: '添加任务',
    );
  }

  Future<void> _openSyncPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SyncDevicesPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _openUpdatePage() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const UpdatePage()));
  }
}

class _AddTodoIntent extends Intent {
  const _AddTodoIntent();
}

class _SearchTodosIntent extends Intent {
  const _SearchTodosIntent();
}

class _SyncTodosIntent extends Intent {
  const _SyncTodosIntent();
}

class _TodoPanel extends StatelessWidget {
  const _TodoPanel({
    required this.controller,
    required this.scrollTodos,
    required this.onAddTodo,
  });

  final AppController controller;
  final bool scrollTodos;
  final VoidCallback onAddTodo;

  @override
  Widget build(BuildContext context) {
    final todos = controller.store.todos;
    final list = _TodoList(
      todos: todos,
      controller: controller,
      shrinkWrap: !scrollTodos,
      historyMode: false,
      emptyLabel: '暂无任务',
      onAddTodo: onAddTodo,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodoOverview(todos: todos),
        const SizedBox(height: 16),
        if (scrollTodos) Expanded(child: list) else list,
      ],
    );
  }
}

class _TodoOverview extends StatelessWidget {
  const _TodoOverview({required this.todos});

  final List<TodoItem> todos;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final active = todos.where((todo) => !todo.completed).length;
    final overdue = todos
        .where(
          (todo) => !todo.completed && todo.dueAt != null && todo.dueAt! < now,
        )
        .length;
    final completed = todos.where((todo) => todo.completed).length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _OverviewTile(
          label: '当前',
          value: active,
          icon: Icons.radio_button_unchecked,
          color: Theme.of(context).colorScheme.primary,
        ),
        _OverviewTile(
          label: '逾期',
          value: overdue,
          icon: Icons.priority_high,
          color: Theme.of(context).colorScheme.error,
        ),
        _OverviewTile(
          label: '完成',
          value: completed,
          icon: Icons.check_circle_outline,
          color: const Color(0xFF2E7D32),
        ),
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoList extends StatelessWidget {
  const _TodoList({
    required this.todos,
    required this.controller,
    required this.historyMode,
    required this.emptyLabel,
    this.shrinkWrap = false,
    this.onAddTodo,
  });

  final List<TodoItem> todos;
  final AppController controller;
  final bool historyMode;
  final String emptyLabel;
  final bool shrinkWrap;
  final VoidCallback? onAddTodo;

  @override
  Widget build(BuildContext context) {
    if (todos.isEmpty) {
      return _TodoEmptyState(label: emptyLabel, onAddTodo: onAddTodo);
    }
    final children = historyMode
        ? _buildHistoryChildren(context)
        : _buildGroupedChildren(context);
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.only(bottom: historyMode ? 16 : 96),
      children: children,
    );
  }

  List<Widget> _buildHistoryChildren(BuildContext context) {
    return [
      for (final todo in todos)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _TodoTile(
            todo: todo,
            controller: controller,
            historyMode: historyMode,
          ),
        ),
    ];
  }

  List<Widget> _buildGroupedChildren(BuildContext context) {
    final active = todos
        .where((todo) => !todo.completed)
        .toList(growable: false);
    final completed = todos
        .where((todo) => todo.completed)
        .toList(growable: false);
    return [
      if (active.isNotEmpty) ...[
        _SectionHeader(label: '进行中', count: active.length),
        for (final todo in active)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TodoTile(
              todo: todo,
              controller: controller,
              historyMode: historyMode,
            ),
          ),
      ],
      if (completed.isNotEmpty) ...[
        const SizedBox(height: 8),
        _SectionHeader(label: '已完成', count: completed.length),
        for (final todo in completed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TodoTile(
              todo: todo,
              controller: controller,
              historyMode: historyMode,
            ),
          ),
      ],
    ];
  }
}

class _TodoEmptyState extends StatelessWidget {
  const _TodoEmptyState({required this.label, this.onAddTodo});

  final String label;
  final VoidCallback? onAddTodo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            if (onAddTodo != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAddTodo,
                icon: const Icon(Icons.add),
                label: const Text('添加任务'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.controller,
    required this.historyMode,
  });

  final TodoItem todo;
  final AppController controller;
  final bool historyMode;

  @override
  Widget build(BuildContext context) {
    final inactive = todo.deleted || todo.completed;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = _todoBorderColor(context, todo);
    final background = todo.deleted
        ? scheme.errorContainer.withValues(alpha: 0.22)
        : todo.completed
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.48)
        : scheme.surface;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: todo.deleted
            ? null
            : () => _showTodoEditorDialog(
                context,
                controller: controller,
                todo: todo,
                title: '编辑任务',
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            leading: todo.deleted
                ? Icon(Icons.history, color: scheme.error)
                : Checkbox(
                    value: todo.completed,
                    onChanged: (value) {
                      controller.store.setCompleted(todo, value ?? false);
                    },
                  ),
            title: Text(
              todo.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                decoration: inactive ? TextDecoration.lineThrough : null,
                color: inactive ? scheme.onSurfaceVariant : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _TodoMetadata(todo: todo, historyMode: historyMode),
            ),
            trailing: todo.deleted
                ? historyMode
                      ? IconButton(
                          tooltip: '恢复',
                          onPressed: () => controller.store.restoreTodo(todo),
                          icon: const Icon(Icons.restore),
                        )
                      : null
                : IconButton(
                    tooltip: '删除',
                    onPressed: () => controller.store.deleteTodo(todo),
                    icon: const Icon(Icons.delete_outline),
                  ),
          ),
        ),
      ),
    );
  }
}

Color _todoBorderColor(BuildContext context, TodoItem todo) {
  final scheme = Theme.of(context).colorScheme;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (todo.deleted) {
    return scheme.error.withValues(alpha: 0.32);
  }
  if (!todo.completed && todo.dueAt != null && todo.dueAt! < now) {
    return scheme.error.withValues(alpha: 0.5);
  }
  if (todo.completed) {
    return scheme.outlineVariant.withValues(alpha: 0.7);
  }
  return scheme.outlineVariant;
}

class _TodoMetadata extends StatelessWidget {
  const _TodoMetadata({required this.todo, required this.historyMode});

  final TodoItem todo;
  final bool historyMode;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final chips = <Widget>[
      _MetaChip(
        icon: Icons.calendar_today,
        label: _formatShortDateTime(todo.createdAt),
      ),
    ];
    if (todo.dueAt != null) {
      final overdue = !todo.completed && !todo.deleted && todo.dueAt! < now;
      chips.add(
        _MetaChip(
          icon: overdue ? Icons.priority_high : Icons.event,
          label:
              '${overdue ? '逾期' : '截止'} ${_formatShortDateTime(todo.dueAt!)}',
          color: overdue ? Theme.of(context).colorScheme.error : null,
        ),
      );
    }
    if (todo.reminderAt != null) {
      chips.add(
        _MetaChip(
          icon: Icons.notifications_none,
          label: _formatShortDateTime(todo.reminderAt!),
        ),
      );
    }
    if (todo.deleted) {
      chips.add(
        _MetaChip(
          icon: Icons.delete_outline,
          label: _formatShortDateTime(todo.updatedAt),
          color: Theme.of(context).colorScheme.error,
        ),
      );
    } else if (todo.completed ||
        (historyMode && todo.updatedAt != todo.createdAt)) {
      chips.add(
        _MetaChip(
          icon: todo.completed ? Icons.check_circle_outline : Icons.update,
          label: todo.completed ? '已完成' : _formatShortDateTime(todo.updatedAt),
          color: todo.completed ? const Color(0xFF2E7D32) : null,
        ),
      );
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: effectiveColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: effectiveColor),
          ),
        ],
      ),
    );
  }
}

Future<void> _showTodoEditorDialog(
  BuildContext context, {
  required AppController controller,
  required String title,
  TodoItem? todo,
}) async {
  final titleController = TextEditingController(text: todo?.title ?? '');
  var dueAt = todo?.dueAt;
  var reminderAt = todo?.reminderAt;
  _TodoEditorResult? result;

  Future<void> pickDateTime({
    required BuildContext dialogContext,
    required void Function(void Function()) setDialogState,
    required int? currentValue,
    required ValueChanged<int?> onChanged,
  }) async {
    final initialDate = currentValue == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(currentValue);
    final date = await showDatePicker(
      context: dialogContext,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !dialogContext.mounted) {
      return;
    }
    final time = await showTimePicker(
      context: dialogContext,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null || !dialogContext.mounted) {
      return;
    }
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).millisecondsSinceEpoch;
    setDialogState(() => onChanged(selected));
  }

  try {
    result = await showDialog<_TodoEditorResult>(
      context: context,
      requestFocus: _shouldAutofocusEditor,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> close([_TodoEditorResult? result]) async {
              FocusManager.instance.primaryFocus?.unfocus();
              await Future<void>.delayed(const Duration(milliseconds: 80));
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(result);
              }
            }

            Future<void> save() async {
              final trimmed = titleController.text.trim();
              if (trimmed.isEmpty) {
                return;
              }
              await close(
                _TodoEditorResult(
                  title: trimmed,
                  dueAt: dueAt,
                  reminderAt: reminderAt,
                ),
              );
            }

            return PopScope<_TodoEditorResult>(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) {
                  close();
                }
              },
              child: AlertDialog(
                title: Text(title),
                scrollable: true,
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: titleController,
                        autofocus: _shouldAutofocusEditor,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: '标题',
                          prefixIcon: Icon(Icons.checklist),
                        ),
                        onSubmitted: (_) => save(),
                      ),
                      const SizedBox(height: 14),
                      _DateTimeField(
                        label: '截止日期',
                        value: dueAt,
                        emptyLabel: '未设置',
                        icon: Icons.event,
                        onPick: () => pickDateTime(
                          dialogContext: dialogContext,
                          setDialogState: setDialogState,
                          currentValue: dueAt,
                          onChanged: (value) => dueAt = value,
                        ),
                        onClear: dueAt == null
                            ? null
                            : () => setDialogState(() => dueAt = null),
                      ),
                      const SizedBox(height: 10),
                      _DateTimeField(
                        label: '提醒时间',
                        value: reminderAt,
                        emptyLabel: '未设置',
                        icon: Icons.notifications_none,
                        onPick: () => pickDateTime(
                          dialogContext: dialogContext,
                          setDialogState: setDialogState,
                          currentValue: reminderAt,
                          onChanged: (value) => reminderAt = value,
                        ),
                        onClear: reminderAt == null
                            ? null
                            : () => setDialogState(() => reminderAt = null),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => close(), child: const Text('取消')),
                  FilledButton(onPressed: save, child: const Text('保存')),
                ],
              ),
            );
          },
        );
      },
    );
  } finally {
    titleController.dispose();
  }
  if (result == null) {
    return;
  }
  if (todo == null) {
    await controller.store.createTodo(
      result.title,
      dueAt: result.dueAt,
      reminderAt: result.reminderAt,
    );
  } else {
    await controller.store.updateTodo(
      todo,
      title: result.title,
      dueAt: result.dueAt,
      reminderAt: result.reminderAt,
    );
  }
}

bool get _shouldAutofocusEditor => !(Platform.isAndroid || Platform.isIOS);

class _TodoEditorResult {
  const _TodoEditorResult({
    required this.title,
    required this.dueAt,
    required this.reminderAt,
  });

  final String title;
  final int? dueAt;
  final int? reminderAt;
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.emptyLabel,
    required this.icon,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final int? value;
  final String emptyLabel;
  final IconData icon;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 2),
                    Text(
                      value == null ? emptyLabel : _formatDateTime(value!),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: value == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear == null)
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant)
              else
                IconButton(
                  tooltip: '清除',
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _HistoryFilter { all, active, completed, deleted }

class _TodoHistorySearchDelegate extends SearchDelegate<void> {
  _TodoHistorySearchDelegate({required this.controller})
    : super(searchFieldLabel: '搜索历史');

  final AppController controller;
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) {
      return null;
    }
    return [
      IconButton(
        tooltip: '清除',
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
        icon: const Icon(Icons.close),
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: '返回',
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _TodoSearchResults(
      controller: controller,
      query: query,
      filter: _filter,
      onFilterChanged: (filter) {
        _filter = filter;
        showResults(context);
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _TodoSearchResults(
      controller: controller,
      query: query,
      filter: _filter,
      onFilterChanged: (filter) {
        _filter = filter;
        showSuggestions(context);
      },
    );
  }
}

class _TodoSearchResults extends StatelessWidget {
  const _TodoSearchResults({
    required this.controller,
    required this.query,
    required this.filter,
    required this.onFilterChanged,
  });

  final AppController controller;
  final String query;
  final _HistoryFilter filter;
  final ValueChanged<_HistoryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final normalizedQuery = query.trim();
        final todos = controller.store
            .searchTodos(normalizedQuery)
            .where(_matchesFilter)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HistoryFilterBar(filter: filter, onFilterChanged: onFilterChanged),
            const Divider(height: 1),
            Expanded(
              child: todos.isEmpty
                  ? Center(
                      child: Text(
                        normalizedQuery.isEmpty ? '还没有历史' : '没有匹配的历史',
                      ),
                    )
                  : _TodoList(
                      todos: todos,
                      controller: controller,
                      historyMode: true,
                      emptyLabel: normalizedQuery.isEmpty ? '还没有历史' : '没有匹配的历史',
                    ),
            ),
          ],
        );
      },
    );
  }

  bool _matchesFilter(TodoItem todo) {
    return switch (filter) {
      _HistoryFilter.all => true,
      _HistoryFilter.active => !todo.deleted && !todo.completed,
      _HistoryFilter.completed => !todo.deleted && todo.completed,
      _HistoryFilter.deleted => todo.deleted,
    };
  }
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
    required this.filter,
    required this.onFilterChanged,
  });

  final _HistoryFilter filter;
  final ValueChanged<_HistoryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _FilterChipButton(
            label: '全部',
            value: _HistoryFilter.all,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: '当前',
            value: _HistoryFilter.active,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: '已完成',
            value: _HistoryFilter.completed,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: '已删除',
            value: _HistoryFilter.deleted,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String label;
  final _HistoryFilter value;
  final _HistoryFilter groupValue;
  final ValueChanged<_HistoryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: value == groupValue,
      onSelected: (_) => onChanged(value),
    );
  }
}

class SyncDevicesPage extends StatefulWidget {
  const SyncDevicesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SyncDevicesPage> createState() => _SyncDevicesPageState();
}

class _SyncDevicesPageState extends State<SyncDevicesPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('同步和设备')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SyncActionGrid(
                    onSync: widget.controller.sync.syncAllTrustedDevices,
                    onShowPairingCode: _showPairingCode,
                    onPair: _openScannerOrManualPair,
                    onExport: _exportBackup,
                  ),
                  const SizedBox(height: 20),
                  _SyncPanel(
                    controller: widget.controller,
                    shrinkWrap: true,
                    showSyncButton: false,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPairingCode() async {
    final pairingInfo = widget.controller.sync.pairingInfo;
    if (pairingInfo == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('配对二维码'),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                  data: pairingInfo.toQrData(),
                  size: 240,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  pairingInfo.baseUrl,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'Token: ${pairingInfo.token}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openScannerOrManualPair() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final data = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => PairScannerPage(onManualPair: _showManualPairDialog),
        ),
      );
      if (data != null && mounted) {
        await _runPairing(() => widget.controller.sync.pairWithQrData(data));
      }
      return;
    }
    await _showManualPairDialog();
  }

  Future<void> _showManualPairDialog() async {
    final urlController = TextEditingController();
    final tokenController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('手动配对'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      labelText: '对方地址',
                      hintText: 'http://192.168.1.20:54321',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tokenController,
                    decoration: const InputDecoration(labelText: '对方 token'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _runPairing(
                    () => widget.controller.sync.pairWith(
                      baseUrl: urlController.text.trim(),
                      token: tokenController.text.trim(),
                    ),
                  );
                },
                child: const Text('配对'),
              ),
            ],
          );
        },
      );
    } finally {
      urlController.dispose();
      tokenController.dispose();
    }
  }

  Future<void> _runPairing(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('配对完成')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('配对失败: $error')));
    }
  }

  Future<void> _exportBackup() async {
    try {
      final path = await widget.controller.store.exportBackup();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('备份已导出: $path')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $error')));
    }
  }
}

class _SyncActionGrid extends StatelessWidget {
  const _SyncActionGrid({
    required this.onSync,
    required this.onShowPairingCode,
    required this.onPair,
    required this.onExport,
  });

  final VoidCallback onSync;
  final VoidCallback onShowPairingCode;
  final VoidCallback onPair;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SyncActionButton(
          filled: true,
          icon: Icons.sync,
          label: '同步',
          onPressed: onSync,
        ),
        _SyncActionButton(
          icon: Icons.qr_code_2,
          label: '配对二维码',
          onPressed: onShowPairingCode,
        ),
        _SyncActionButton(
          icon: Icons.qr_code_scanner,
          label: '扫码/手动配对',
          onPressed: onPair,
        ),
        _SyncActionButton(
          icon: Icons.download,
          label: '导出备份',
          onPressed: onExport,
        ),
      ],
    );
  }
}

class _SyncActionButton extends StatelessWidget {
  const _SyncActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon), const SizedBox(width: 8), Text(label)],
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(150, 48)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    if (filled) {
      return FilledButton(onPressed: onPressed, style: style, child: child);
    }
    return OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class _SyncPanel extends StatelessWidget {
  const _SyncPanel({
    required this.controller,
    this.shrinkWrap = false,
    this.showSyncButton = true,
  });

  final AppController controller;
  final bool shrinkWrap;
  final bool showSyncButton;

  @override
  Widget build(BuildContext context) {
    final localUrl = controller.sync.localBaseUrl ?? 'starting';
    final trusted = controller.store.trustedDevices;
    final discovered = controller.sync.discoveredPeers;
    final children = [
      _SyncSection(
        title: '本机状态',
        icon: Icons.dns_outlined,
        children: [
          _InfoRow(label: '设备', value: controller.store.device.name),
          _InfoRow(
            label: 'ID',
            value: controller.store.device.deviceId.substring(0, 8),
          ),
          _InfoRow(label: '地址', value: localUrl),
          const SizedBox(height: 8),
          _StatusPill(text: controller.sync.status),
          if (showSyncButton) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: controller.sync.syncAllTrustedDevices,
                icon: const Icon(Icons.sync),
                label: const Text('同步所有已配对设备'),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      _SyncSection(
        title: '已配对设备',
        icon: Icons.verified_outlined,
        children: [
          if (trusted.isEmpty)
            const _SectionEmptyText('还没有配对设备')
          else
            for (final device in trusted)
              _DeviceTile(
                icon: Icons.devices,
                title: device.name,
                subtitle: device.baseUrl,
                trailing: IconButton(
                  tooltip: '同步',
                  onPressed: () =>
                      controller.sync.syncWithTrustedDevice(device),
                  icon: const Icon(Icons.sync),
                ),
              ),
        ],
      ),
      const SizedBox(height: 16),
      _SyncSection(
        title: '局域网发现',
        icon: Icons.wifi_tethering,
        children: [
          if (discovered.isEmpty)
            const _SectionEmptyText('未发现其他 MyTodo 设备')
          else
            for (final peer in discovered)
              _DeviceTile(
                icon: peer.trusted ? Icons.verified : Icons.devices,
                title: peer.name,
                subtitle: peer.baseUrl,
                trailing: _PeerBadge(trusted: peer.trusted),
              ),
        ],
      ),
    ];
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      children: children,
    );
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: scheme.primary),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }
}

class _PeerBadge extends StatelessWidget {
  const _PeerBadge({required this.trusted});

  final bool trusted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = trusted ? const Color(0xFF2E7D32) : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        trusted ? '已配对' : '未配对',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _SectionEmptyText extends StatelessWidget {
  const _SectionEmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class PairScannerPage extends StatefulWidget {
  const PairScannerPage({super.key, required this.onManualPair});

  final Future<void> Function() onManualPair;

  @override
  State<PairScannerPage> createState() => _PairScannerPageState();
}

class _PairScannerPageState extends State<PairScannerPage> {
  late final MobileScannerController _scannerController =
      MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码配对'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await widget.onManualPair();
            },
            child: const Text('手动'),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _scannerController,
        errorBuilder: _buildScannerError,
        onDetect: (capture) {
          if (_handled) {
            return;
          }
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code == null) {
            return;
          }
          _handled = true;
          Navigator.of(context).pop(code);
        },
      ),
    );
  }

  Widget _buildScannerError(
    BuildContext context,
    MobileScannerException error,
  ) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => '没有相机权限，无法扫码配对。',
      MobileScannerErrorCode.unsupported => '当前设备不支持扫码。',
      _ => '相机启动失败，请重试或使用手动配对。',
    };
    final detail = error.errorDetails?.message;

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner, color: Colors.white, size: 44),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    _scannerController.start();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await widget.onManualPair();
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('手动配对'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(int value) {
  final time = DateTime.fromMillisecondsSinceEpoch(value);
  final year = time.year.toString().padLeft(4, '0');
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

String _formatShortDateTime(int value) {
  final time = DateTime.fromMillisecondsSinceEpoch(value);
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}
