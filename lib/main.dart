import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_controller.dart';
import 'src/data/todo_models.dart';
import 'src/desktop/windows_tray.dart';
import 'src/search/history_search.dart';
import 'src/sync/supabase_sync_service.dart';
import 'src/ui/theme/app_theme.dart';
import 'src/ui/nav_views.dart';
import 'src/ui/reorder_items.dart';
import 'src/ui/todo_view_filter.dart';
import 'src/update/update_page.dart';

const Color _appAccent = Color(0xFF0F766E);
const Color _appBackground = Color(0xFFF5FAF8);

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
      localizationsDelegates: fluent.FluentLocalizations.localizationsDelegates,
      supportedLocales: fluent.FluentLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _appAccent,
          brightness: Brightness.light,
        ),
        fontFamily: 'Microsoft YaHei UI',
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
      builder: (context, child) {
        return fluent.FluentTheme(
          data: AppTheme.lightTheme(),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
  const TodoHome({
    super.key,
    required this.controller,
    this.enableWindowsTray = true,
  });

  final AppController controller;
  final bool enableWindowsTray;

  @override
  State<TodoHome> createState() => _TodoHomeState();
}

class _TodoHomeState extends State<TodoHome> {
  WindowsTrayController? _windowsTrayController;
  bool _syncingFromHome = false;
  String _selectedListId = TodoList.inboxId;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows && widget.enableWindowsTray) {
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
              unawaited(_syncFromHome(showResult: true));
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final store = widget.controller.store;
              final entries = buildNavEntries(store);
              final selectedEntry = _selectedEntry(entries);
              return Scaffold(
                backgroundColor: _appBackground,
                body: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 760;
                      return _FluentTodoNavigationLayout(
                        entries: entries,
                        selectedEntry: selectedEntry,
                        controller: widget.controller,
                        compact: compact,
                        syncing: _syncingFromHome,
                        onSelected: (id) {
                          setState(() => _selectedListId = id);
                        },
                        onAddTodo: _showAddTodoDialog,
                        onAddList: _showAddListDialog,
                        onSearch: _openHistorySearch,
                        onUpdate: _openUpdatePage,
                        onSync: _syncingFromHome
                            ? null
                            : () => unawaited(_syncFromHome(showResult: true)),
                        onSyncPage: _openSyncPage,
                        onRefresh: _syncFromHome,
                      );
                    },
                  ),
                ),
                floatingActionButton: FloatingActionButton.extended(
                  onPressed: _showAddTodoDialog,
                  backgroundColor: _appAccent,
                  foregroundColor: Colors.white,
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

  TodoNavEntry _selectedEntry(List<TodoNavEntry> entries) {
    for (final entry in entries) {
      if (entry.id == _selectedListId) {
        return entry;
      }
    }
    _selectedListId = TodoList.inboxId;
    return entries.firstWhere(
      (entry) => entry.id == TodoList.inboxId,
      orElse: () => entries.first,
    );
  }

  String _targetListIdForNewTodo() {
    return targetListIdForNewTodoView(_selectedListId);
  }

  bool get _newTodoImportant => defaultImportantForNewTodoView(_selectedListId);

  Future<void> _openHistorySearch() async {
    await showSearch<void>(
      context: context,
      delegate: TodoHistorySearchDelegate(
        listenable: widget.controller,
        searchTodos: widget.controller.store.searchTodos,
        itemBuilder: (context, todo) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TodoTile(
              todo: todo,
              controller: widget.controller,
              historyMode: true,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddTodoDialog() async {
    await _showTodoEditorDialog(
      context,
      controller: widget.controller,
      title: '添加任务',
      initialListId: _targetListIdForNewTodo(),
      initialDueAt: _initialDueAtForNewTodo(),
      initialImportant: _newTodoImportant,
    );
  }

  int? _initialDueAtForNewTodo() {
    return defaultDueAtForNewTodoView(_selectedListId, DateTime.now());
  }

  Future<void> _showAddListDialog() async {
    final list = await _showTodoListEditorDialog(
      context,
      controller: widget.controller,
    );
    if (list != null && mounted) {
      setState(() => _selectedListId = list.id);
    }
  }

  Future<void> _openSyncPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RemoteSyncPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _openUpdatePage() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const UpdatePage()));
  }

  Future<void> _syncFromHome({bool showResult = false}) async {
    if (_syncingFromHome) {
      return;
    }
    if (mounted) {
      setState(() => _syncingFromHome = true);
    }
    try {
      if (!widget.controller.supabaseSync.config.canSync) {
        if (showResult && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('远程同步未配置，无法同步')));
        }
        return;
      }
      await widget.controller.supabaseSync.syncNow();
      if (showResult && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('远程同步完成')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('同步失败: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _syncingFromHome = false);
      }
    }
  }
}

class _FluentTodoNavigationLayout extends StatefulWidget {
  const _FluentTodoNavigationLayout({
    required this.entries,
    required this.selectedEntry,
    required this.controller,
    required this.compact,
    required this.syncing,
    required this.onSelected,
    required this.onAddTodo,
    required this.onAddList,
    required this.onSearch,
    required this.onUpdate,
    required this.onSync,
    required this.onSyncPage,
    required this.onRefresh,
  });

  final List<TodoNavEntry> entries;
  final TodoNavEntry selectedEntry;
  final AppController controller;
  final bool compact;
  final bool syncing;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddTodo;
  final VoidCallback onAddList;
  final VoidCallback onSearch;
  final VoidCallback onUpdate;
  final VoidCallback? onSync;
  final VoidCallback onSyncPage;
  final Future<void> Function() onRefresh;

  @override
  State<_FluentTodoNavigationLayout> createState() =>
      _FluentTodoNavigationLayoutState();
}

class _FluentTodoNavigationLayoutState
    extends State<_FluentTodoNavigationLayout> {
  bool _desktopPaneExpanded = true;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = widget.entries.indexWhere(
      (entry) => entry.id == widget.selectedEntry.id,
    );
    if (widget.compact) {
      return _CompactTodoDrawerLayout(
        entries: widget.entries,
        selectedEntry: widget.selectedEntry,
        controller: widget.controller,
        syncing: widget.syncing,
        onSelected: widget.onSelected,
        onAddTodo: widget.onAddTodo,
        onAddList: widget.onAddList,
        onSearch: widget.onSearch,
        onUpdate: widget.onUpdate,
        onSync: widget.onSync,
        onSyncPage: widget.onSyncPage,
        onRefresh: widget.onRefresh,
      );
    }
    final paneDisplayMode = _desktopPaneExpanded
        ? fluent.PaneDisplayMode.expanded
        : fluent.PaneDisplayMode.compact;
    return fluent.NavigationView(
      contentShape: const RoundedRectangleBorder(),
      pane: fluent.NavigationPane(
        selected: selectedIndex < 0 ? 0 : selectedIndex,
        displayMode: paneDisplayMode,
        toggleButton: Tooltip(
          message: _desktopPaneExpanded ? '收起侧边栏' : '展开侧边栏',
          child: IconButton(
            icon: Icon(_desktopPaneExpanded ? Icons.menu_open : Icons.menu),
            onPressed: () {
              setState(() => _desktopPaneExpanded = !_desktopPaneExpanded);
            },
          ),
        ),
        size: fluent.NavigationPaneSize(
          compactWidth: 56,
          openWidth: 320,
          openMaxWidth: 340,
        ),
        header: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12),
          child: Text(
            'MyTodo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: fluent.FluentTheme.of(context).typography.subtitle,
          ),
        ),
        items: [
          for (final entry in widget.entries)
            fluent.PaneItem(
              icon: Icon(entry.icon, color: entry.accent),
              title: Text(entry.name),
              infoBadge: _countBadge(
                widget.controller.store.activeCountFor(entry.id),
              ),
              body: _FluentMainContent(
                entry: entry,
                controller: widget.controller,
                compact: false,
                syncing: widget.syncing,
                onAddTodo: widget.onAddTodo,
                onSearch: widget.onSearch,
                onUpdate: widget.onUpdate,
                onSync: widget.onSync,
                onSyncPage: widget.onSyncPage,
                onRefresh: widget.onRefresh,
              ),
            ),
        ],
        footerItems: [
          fluent.PaneItemAction(
            icon: const Icon(Icons.add),
            title: const Text('添加任务'),
            onTap: widget.onAddTodo,
          ),
          fluent.PaneItemAction(
            icon: const Icon(Icons.add_circle_outline),
            title: const Text('添加清单'),
            onTap: widget.onAddList,
          ),
          fluent.PaneItemSeparator(),
          fluent.PaneItemAction(
            icon: const Icon(Icons.search),
            title: const Text('搜索'),
            onTap: widget.onSearch,
          ),
          fluent.PaneItemAction(
            icon: const Icon(Icons.system_update),
            title: const Text('检查更新'),
            onTap: widget.onUpdate,
          ),
          fluent.PaneItemAction(
            icon: widget.syncing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            title: Text(widget.syncing ? '同步中' : '立即同步'),
            enabled: widget.onSync != null,
            onTap: widget.onSync ?? () {},
          ),
          fluent.PaneItemAction(
            icon: const Icon(Icons.devices),
            title: const Text('远程同步'),
            onTap: widget.onSyncPage,
          ),
        ],
        onChanged: (index) {
          if (index >= 0 && index < widget.entries.length) {
            widget.onSelected(widget.entries[index].id);
          }
        },
      ),
    );
  }

  fluent.InfoBadge? _countBadge(int count) {
    if (count <= 0) {
      return null;
    }
    return fluent.InfoBadge(
      source: Text(count.toString()),
      color: _appAccent,
      foregroundColor: Colors.white,
    );
  }
}

class _CompactTodoDrawerLayout extends StatelessWidget {
  const _CompactTodoDrawerLayout({
    required this.entries,
    required this.selectedEntry,
    required this.controller,
    required this.syncing,
    required this.onSelected,
    required this.onAddTodo,
    required this.onAddList,
    required this.onSearch,
    required this.onUpdate,
    required this.onSync,
    required this.onSyncPage,
    required this.onRefresh,
  });

  final List<TodoNavEntry> entries;
  final TodoNavEntry selectedEntry;
  final AppController controller;
  final bool syncing;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddTodo;
  final VoidCallback onAddList;
  final VoidCallback onSearch;
  final VoidCallback onUpdate;
  final VoidCallback? onSync;
  final VoidCallback onSyncPage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _appBackground,
      drawer: Drawer(
        width: 304,
        backgroundColor: const Color(0xFFF7FAF9),
        shape: const RoundedRectangleBorder(),
        child: SafeArea(
          child: _CompactNavigationDrawer(
            entries: entries,
            selectedEntry: selectedEntry,
            controller: controller,
            onSelected: onSelected,
            onAddTodo: onAddTodo,
            onAddList: onAddList,
            onSearch: onSearch,
            onUpdate: onUpdate,
            onSync: onSync,
            onSyncPage: onSyncPage,
            syncing: syncing,
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          return _FluentMainContent(
            entry: selectedEntry,
            controller: controller,
            compact: true,
            syncing: syncing,
            onAddTodo: onAddTodo,
            onSearch: onSearch,
            onUpdate: onUpdate,
            onSync: onSync,
            onSyncPage: onSyncPage,
            onRefresh: onRefresh,
            onOpenNavigation: Scaffold.of(context).openDrawer,
          );
        },
      ),
    );
  }
}

class _CompactNavigationDrawer extends StatelessWidget {
  const _CompactNavigationDrawer({
    required this.entries,
    required this.selectedEntry,
    required this.controller,
    required this.onSelected,
    required this.onAddTodo,
    required this.onAddList,
    required this.onSearch,
    required this.onUpdate,
    required this.onSync,
    required this.onSyncPage,
    required this.syncing,
  });

  final List<TodoNavEntry> entries;
  final TodoNavEntry selectedEntry;
  final AppController controller;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddTodo;
  final VoidCallback onAddList;
  final VoidCallback onSearch;
  final VoidCallback onUpdate;
  final VoidCallback? onSync;
  final VoidCallback onSyncPage;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
          child: Text(
            'MyTodo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF123F3B),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final entry in entries)
                _CompactNavigationTile(
                  entry: entry,
                  count: controller.store.activeCountFor(entry.id),
                  selected: entry.id == selectedEntry.id,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(entry.id);
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        _DrawerActionTile(
          icon: Icons.add,
          label: '添加任务',
          onTap: () {
            Navigator.of(context).pop();
            onAddTodo();
          },
        ),
        _DrawerActionTile(
          icon: Icons.add_circle_outline,
          label: '添加清单',
          onTap: () {
            Navigator.of(context).pop();
            onAddList();
          },
        ),
        const Divider(height: 1),
        _DrawerActionTile(
          icon: Icons.search,
          label: '搜索',
          onTap: () {
            Navigator.of(context).pop();
            onSearch();
          },
        ),
        _DrawerActionTile(
          icon: Icons.system_update,
          label: '检查更新',
          onTap: () {
            Navigator.of(context).pop();
            onUpdate();
          },
        ),
        _DrawerActionTile(
          icon: Icons.sync,
          label: syncing ? '同步中' : '立即同步',
          enabled: onSync != null,
          trailing: syncing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: () {
            Navigator.of(context).pop();
            onSync?.call();
          },
        ),
        _DrawerActionTile(
          icon: Icons.devices,
          label: '远程同步',
          onTap: () {
            Navigator.of(context).pop();
            onSyncPage();
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CompactNavigationTile extends StatelessWidget {
  const _CompactNavigationTile({
    required this.entry,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final TodoNavEntry entry;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? _appAccent : const Color(0xFF274B47);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        selected: selected,
        selectedTileColor: _appAccent.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(entry.icon, color: selected ? _appAccent : entry.accent),
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        trailing: count > 0 ? _DrawerCountBadge(count: count) : null,
        onTap: onTap,
      ),
    );
  }
}

class _DrawerActionTile extends StatelessWidget {
  const _DrawerActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: const Color(0xFF0E4D49)),
      title: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF123F3B),
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: trailing,
      onTap: enabled ? onTap : null,
    );
  }
}

class _DrawerCountBadge extends StatelessWidget {
  const _DrawerCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _appAccent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count.toString(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FluentMainContent extends StatelessWidget {
  const _FluentMainContent({
    required this.entry,
    required this.controller,
    required this.compact,
    required this.syncing,
    required this.onAddTodo,
    required this.onSearch,
    required this.onUpdate,
    required this.onSync,
    required this.onSyncPage,
    required this.onRefresh,
    this.onOpenNavigation,
  });

  final TodoNavEntry entry;
  final AppController controller;
  final bool compact;
  final bool syncing;
  final VoidCallback onAddTodo;
  final VoidCallback onSearch;
  final VoidCallback onUpdate;
  final VoidCallback? onSync;
  final VoidCallback onSyncPage;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenNavigation;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (onOpenNavigation != null)
          _MobileNavigationBar(onOpenNavigation: onOpenNavigation!),
        Expanded(
          child: _TodoContentPage(
            entry: entry,
            controller: controller,
            onAddTodo: onAddTodo,
            onRefresh: onRefresh,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _MobileNavigationBar extends StatelessWidget {
  const _MobileNavigationBar({required this.onOpenNavigation});

  final VoidCallback onOpenNavigation;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE1E9E7))),
      ),
      child: Row(
        children: [
          _TopIconButton(
            tooltip: '打开侧边栏',
            icon: Icons.menu,
            onTap: onOpenNavigation,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        color: const Color(0xFF0E4D49),
      ),
    );
  }
}

class _TodoContentPage extends StatefulWidget {
  const _TodoContentPage({
    required this.entry,
    required this.controller,
    required this.onAddTodo,
    this.onRefresh,
    this.compact = false,
  });

  final TodoNavEntry entry;
  final AppController controller;
  final VoidCallback onAddTodo;
  final Future<void> Function()? onRefresh;
  final bool compact;

  @override
  State<_TodoContentPage> createState() => _TodoContentPageState();
}

class _TodoContentPageState extends State<_TodoContentPage> {
  TodoViewFilter _filter = TodoViewFilter.active;

  @override
  Widget build(BuildContext context) {
    final todos = widget.controller.store.visibleTodosForList(widget.entry.id);
    final filteredTodos = filterTodosByView(
      todos,
      _filter,
      DateTime.now().millisecondsSinceEpoch,
    );
    final list = _TodoList(
      todos: filteredTodos,
      controller: widget.controller,
      historyMode: false,
      emptyLabel: _emptyLabel,
      onAddTodo: widget.onAddTodo,
      onReorder: widget.controller.store.reorderTodos,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Padding(
          padding: widget.compact
              ? const EdgeInsets.fromLTRB(12, 14, 12, 0)
              : const EdgeInsets.fromLTRB(24, 32, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ContentHeader(entry: widget.entry),
              const SizedBox(height: 16),
              _TodoOverview(
                todos: todos,
                selectedFilter: _filter,
                onFilterChanged: (filter) {
                  setState(() => _filter = filter);
                },
              ),
              const SizedBox(height: 20),
              Expanded(
                child: widget.onRefresh == null
                    ? list
                    : RefreshIndicator(
                        onRefresh: widget.onRefresh!,
                        child: list,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _emptyLabel {
    return switch (_filter) {
      TodoViewFilter.active => '暂无当前任务',
      TodoViewFilter.overdue => '没有逾期任务',
      TodoViewFilter.completed => '还没有已完成任务',
    };
  }
}

class _ContentHeader extends StatelessWidget {
  const _ContentHeader({required this.entry});

  final TodoNavEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: entry.accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(entry.icon, color: entry.accent, size: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF123F3B),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.isVirtual
                      ? subtitleForView(entry.id)
                      : '按完成状态查看和处理当前清单任务',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4D6B68),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

class _TodoPanel extends StatefulWidget {
  const _TodoPanel({
    required this.controller,
    required this.scrollTodos,
    required this.onAddTodo,
  });

  final AppController controller;
  final bool scrollTodos;
  final VoidCallback onAddTodo;

  @override
  State<_TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<_TodoPanel> {
  TodoViewFilter _filter = TodoViewFilter.active;

  @override
  Widget build(BuildContext context) {
    final todos = widget.controller.store.todos;
    final filteredTodos = filterTodosByView(
      todos,
      _filter,
      DateTime.now().millisecondsSinceEpoch,
    );
    final list = _TodoList(
      todos: filteredTodos,
      controller: widget.controller,
      shrinkWrap: !widget.scrollTodos,
      historyMode: false,
      emptyLabel: _emptyLabel,
      onAddTodo: widget.onAddTodo,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodoOverview(
          todos: todos,
          selectedFilter: _filter,
          onFilterChanged: (filter) {
            setState(() => _filter = filter);
          },
        ),
        const SizedBox(height: 16),
        if (widget.scrollTodos) Expanded(child: list) else list,
      ],
    );
  }

  String get _emptyLabel {
    return switch (_filter) {
      TodoViewFilter.active => '暂无当前任务',
      TodoViewFilter.overdue => '没有逾期任务',
      TodoViewFilter.completed => '还没有已完成任务',
    };
  }
}

class _TodoOverview extends StatelessWidget {
  const _TodoOverview({
    required this.todos,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  final List<TodoItem> todos;
  final TodoViewFilter selectedFilter;
  final ValueChanged<TodoViewFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final counts = countTodosByView(todos, now);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _OverviewTile(
          label: '当前',
          value: counts.active,
          icon: Icons.radio_button_unchecked,
          selected: selectedFilter == TodoViewFilter.active,
          color: Theme.of(context).colorScheme.primary,
          onTap: () => onFilterChanged(TodoViewFilter.active),
        ),
        _OverviewTile(
          label: '逾期',
          value: counts.overdue,
          icon: Icons.priority_high,
          selected: selectedFilter == TodoViewFilter.overdue,
          color: Theme.of(context).colorScheme.error,
          onTap: () => onFilterChanged(TodoViewFilter.overdue),
        ),
        _OverviewTile(
          label: '完成',
          value: counts.completed,
          icon: Icons.check_circle_outline,
          selected: selectedFilter == TodoViewFilter.completed,
          color: const Color(0xFF2E7D32),
          onTap: () => onFilterChanged(TodoViewFilter.completed),
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
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? color.withValues(alpha: 0.14)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.52);
    final borderColor = selected ? color : scheme.outlineVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 112,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
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
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? color : null,
                    fontWeight: selected ? FontWeight.w700 : null,
                  ),
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
        ),
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
    this.onReorder,
  });

  final List<TodoItem> todos;
  final AppController controller;
  final bool historyMode;
  final String emptyLabel;
  final bool shrinkWrap;
  final VoidCallback? onAddTodo;
  final Future<void> Function(List<TodoItem> orderedTodos)? onReorder;

  @override
  Widget build(BuildContext context) {
    if (todos.isEmpty) {
      if (!shrinkWrap) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: _TodoEmptyState(
                    label: emptyLabel,
                    onAddTodo: onAddTodo,
                  ),
                ),
              ],
            );
          },
        );
      }
      return _TodoEmptyState(label: emptyLabel, onAddTodo: onAddTodo);
    }
    final children = _buildListChildren(context);
    if (!historyMode && !shrinkWrap && onReorder != null) {
      return ReorderableListView(
        buildDefaultDragHandles: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        onReorderItem: (oldIndex, newIndex) {
          unawaited(onReorder!(reorderItems(todos, oldIndex, newIndex)));
        },
        children: children,
      );
    }
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: historyMode ? 16 : 96),
      children: children,
    );
  }

  List<Widget> _buildListChildren(BuildContext context) {
    return [
      for (var index = 0; index < todos.length; index++)
        Padding(
          key: ValueKey(todos[index].id),
          padding: const EdgeInsets.only(bottom: 8),
          child: _TodoTile(
            todo: todos[index],
            controller: controller,
            historyMode: historyMode,
            reorderIndex: !historyMode && !shrinkWrap && onReorder != null
                ? index
                : null,
          ),
        ),
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

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.controller,
    required this.historyMode,
    this.reorderIndex,
  });

  final TodoItem todo;
  final AppController controller;
  final bool historyMode;
  final int? reorderIndex;

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
            trailing: _TodoTileActions(
              todo: todo,
              historyMode: historyMode,
              reorderIndex: reorderIndex,
              onDelete: () => controller.store.deleteTodo(todo),
              onRestore: () => controller.store.restoreTodo(todo),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodoTileActions extends StatelessWidget {
  const _TodoTileActions({
    required this.todo,
    required this.historyMode,
    required this.onDelete,
    required this.onRestore,
    this.reorderIndex,
  });

  final TodoItem todo;
  final bool historyMode;
  final int? reorderIndex;
  final VoidCallback onDelete;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];
    final index = reorderIndex;
    if (!todo.deleted && index != null) {
      actions.add(
        Tooltip(
          message: '拖动排序',
          child: ReorderableDragStartListener(
            index: index,
            child: const SizedBox.square(
              dimension: 40,
              child: Icon(Icons.drag_handle),
            ),
          ),
        ),
      );
    }
    if (todo.deleted) {
      if (historyMode) {
        actions.add(
          IconButton(
            tooltip: '恢复',
            onPressed: onRestore,
            icon: const Icon(Icons.restore),
          ),
        );
      }
    } else {
      actions.add(
        IconButton(
          tooltip: '删除',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      );
    }
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }
}

Color _todoBorderColor(BuildContext context, TodoItem todo) {
  final scheme = Theme.of(context).colorScheme;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (todo.deleted) {
    return scheme.error.withValues(alpha: 0.32);
  }
  if (!todo.completed && isTodoOverdue(todo, now)) {
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
      final overdue =
          !todo.completed && !todo.deleted && isTodoOverdue(todo, now);
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
  String initialListId = TodoList.inboxId,
  int? initialDueAt,
  bool initialImportant = false,
}) async {
  final titleController = TextEditingController(text: todo?.title ?? '');
  var dueAt = todo?.dueAt ?? initialDueAt;
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
      listId: initialListId,
      dueAt: result.dueAt,
      reminderAt: result.reminderAt,
      important: initialImportant,
    );
  } else {
    await controller.store.updateTodo(
      todo,
      title: result.title,
      dueAt: result.dueAt,
      reminderAt: result.reminderAt,
      listId: todo.listId,
    );
  }
}

Future<TodoList?> _showTodoListEditorDialog(
  BuildContext context, {
  required AppController controller,
}) async {
  final nameController = TextEditingController();
  final initialColor =
      kListColorPalette[controller.store.lists.length %
          kListColorPalette.length];
  var selectedColor = initialColor;
  _TodoListEditorResult? result;

  try {
    result = await showDialog<_TodoListEditorResult>(
      context: context,
      requestFocus: _shouldAutofocusEditor,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> close([_TodoListEditorResult? result]) async {
              FocusManager.instance.primaryFocus?.unfocus();
              await Future<void>.delayed(const Duration(milliseconds: 80));
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(result);
              }
            }

            Future<void> save() async {
              final trimmed = nameController.text.trim();
              if (trimmed.isEmpty) {
                return;
              }
              await close(
                _TodoListEditorResult(
                  name: trimmed,
                  color: selectedColor.toARGB32(),
                ),
              );
            }

            return PopScope<_TodoListEditorResult>(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) {
                  close();
                }
              },
              child: AlertDialog(
                title: const Text('添加清单'),
                scrollable: true,
                content: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameController,
                        autofocus: _shouldAutofocusEditor,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: '清单名称',
                          prefixIcon: Icon(Icons.list_alt),
                        ),
                        onSubmitted: (_) => save(),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final color in kListColorPalette)
                            _ListColorChoice(
                              color: color,
                              selected: color == selectedColor,
                              onTap: () {
                                setDialogState(() => selectedColor = color);
                              },
                            ),
                        ],
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
    nameController.dispose();
  }

  if (result == null) {
    return null;
  }
  return controller.store.createTodoList(result.name, color: result.color);
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

class _TodoListEditorResult {
  const _TodoListEditorResult({required this.name, required this.color});

  final String name;
  final int color;
}

class _ListColorChoice extends StatelessWidget {
  const _ListColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '清单颜色',
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
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

class RemoteSyncPage extends StatefulWidget {
  const RemoteSyncPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<RemoteSyncPage> createState() => _RemoteSyncPageState();
}

class _RemoteSyncPageState extends State<RemoteSyncPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('远程同步')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SupabaseSyncSection(
                    controller: widget.controller,
                    onSync: _syncRemote,
                    onSettings: _showSupabaseSettings,
                    onTest: _testSupabase,
                  ),
                  const SizedBox(height: 16),
                  _SyncSection(
                    title: '备份',
                    icon: Icons.download,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _exportBackup,
                          icon: const Icon(Icons.download),
                          label: const Text('导出备份'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _syncRemote() async {
    if (!widget.controller.supabaseSync.config.canSync) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('远程同步未配置，无法同步')));
      return;
    }
    try {
      await widget.controller.supabaseSync.syncNow();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('远程同步完成')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('同步失败: $error')));
    }
  }

  Future<void> _testSupabase() async {
    try {
      await widget.controller.supabaseSync.testConnection();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Supabase 连接正常')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Supabase 连接失败: $error')));
    }
  }

  Future<void> _showSupabaseSettings() async {
    final config = widget.controller.supabaseSync.config;
    final restUrlController = TextEditingController(text: config.restUrl);
    final keyController = TextEditingController(text: config.publishableKey);
    final tableController = TextEditingController(text: config.tableName);
    final spaceController = TextEditingController(text: config.syncSpace);
    var enabled = config.enabled;
    try {
      final result = await showDialog<SupabaseSyncConfig>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Supabase 远程同步'),
                scrollable: true,
                content: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用远程同步'),
                        value: enabled,
                        onChanged: (value) {
                          setDialogState(() => enabled = value);
                        },
                      ),
                      const Text('启用后，本地任务变化会自动触发远程同步。'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: restUrlController,
                        decoration: const InputDecoration(
                          labelText: 'REST API URL',
                          hintText: 'https://xxxx.supabase.co/rest/v1',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: keyController,
                        decoration: const InputDecoration(
                          labelText: 'Publishable key',
                          hintText: 'sb_publishable_...',
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tableController,
                        decoration: const InputDecoration(
                          labelText: '事件表名',
                          hintText: 'mytodo_events',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: spaceController,
                        decoration: const InputDecoration(
                          labelText: '同步空间',
                          hintText: 'family 或个人空间名',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const _WarningText(
                        '客户端只允许填写 publishable key。不要填写 secret key；secret key 一旦进入 APK/EXE 就会泄露。',
                      ),
                      const SizedBox(height: 8),
                      const SelectableText(
                        '表结构需包含 sync_space、event_id、device_id、seq、timestamp、type、todo_id、payload_json 字段。',
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
                    onPressed: () {
                      Navigator.of(context).pop(
                        SupabaseSyncConfig(
                          enabled: enabled,
                          autoSync: SupabaseSyncConfig.defaultAutoSync,
                          restUrl: restUrlController.text,
                          publishableKey: keyController.text,
                          tableName: tableController.text,
                          syncSpace: spaceController.text,
                        ),
                      );
                    },
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (result == null) {
        return;
      }
      await widget.controller.supabaseSync.saveConfig(result);
    } finally {
      restUrlController.dispose();
      keyController.dispose();
      tableController.dispose();
      spaceController.dispose();
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

class _SupabaseSyncSection extends StatelessWidget {
  const _SupabaseSyncSection({
    required this.controller,
    required this.onSync,
    required this.onSettings,
    required this.onTest,
  });

  final AppController controller;
  final VoidCallback onSync;
  final VoidCallback onSettings;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final config = controller.supabaseSync.config;
    final scheme = Theme.of(context).colorScheme;
    final enabledColor = config.enabled
        ? const Color(0xFF2E7D32)
        : scheme.onSurfaceVariant;
    return _SyncSection(
      title: 'Supabase 远程同步',
      icon: Icons.cloud_sync_outlined,
      children: [
        Row(
          children: [
            Icon(
              config.enabled ? Icons.cloud_done : Icons.cloud_off,
              color: enabledColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                config.enabled ? '已启用' : '未启用',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: enabledColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _InfoRow(label: '地址', value: config.restUrl),
        _InfoRow(label: '表', value: config.tableName),
        _InfoRow(label: '空间', value: config.syncSpace),
        const _InfoRow(label: '自动', value: '本地变化后立即同步'),
        const SizedBox(height: 8),
        _StatusPill(text: controller.supabaseSync.status),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: config.canSync && !controller.supabaseSync.busy
                  ? onSync
                  : null,
              icon: const Icon(Icons.cloud_sync),
              label: const Text('立即远程同步'),
            ),
            OutlinedButton.icon(
              onPressed: controller.supabaseSync.busy ? null : onTest,
              icon: const Icon(Icons.network_check),
              label: const Text('测试连接'),
            ),
            OutlinedButton.icon(
              onPressed: controller.supabaseSync.busy ? null : onSettings,
              icon: const Icon(Icons.settings),
              label: const Text('配置'),
            ),
          ],
        ),
      ],
    );
  }
}

class _WarningText extends StatelessWidget {
  const _WarningText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber, color: scheme.error, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: scheme.error)),
        ),
      ],
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
