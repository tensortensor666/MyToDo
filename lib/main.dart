import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart' as window_manager;

import 'src/app_controller.dart';
import 'src/data/todo_models.dart';
import 'src/desktop/windows_tray.dart';
import 'src/search/history_search.dart';
import 'src/sync/supabase_sync_service.dart';
import 'src/ui/theme/app_theme.dart';
import 'src/ui/nav_views.dart';
import 'src/ui/important_toggle_button.dart';
import 'src/ui/reorder_items.dart';
import 'src/ui/todo_view_filter.dart';
import 'src/update/update_page.dart';

const Color _appAccent = Color(0xFFC96442);
const Color _appAccentOn = Color(0xFFFAF9F5);
const Color _appBackground = Color(0xFFF5F4ED);
const Color _appSurface = Color(0xFFFAF9F5);
const Color _appSurfaceWarm = Color(0xFFE8E6DC);
const Color _appForeground = Color(0xFF141413);
const Color _appForegroundSoft = Color(0xFF3D3D3A);
const Color _appMuted = Color(0xFF5E5D59);
const Color _appMeta = Color(0xFF87867F);
const Color _appBorder = Color(0xFFF0EEE6);
const Color _appBorderSoft = Color(0xFFE8E6DC);
const Color _appDanger = Color(0xFFB53333);
const Color _appSuccess = Color(0xFF17A34A);
const String _appVersionLabel = 'v1.4.8';

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
          surface: _appSurface,
          error: _appDanger,
        ),
        fontFamily: 'Microsoft YaHei UI',
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: _appBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: _appAccent, width: 1.4),
            borderRadius: BorderRadius.circular(12),
          ),
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
                        onDeleteList: _deleteTodoList,
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

  Future<void> _deleteTodoList(TodoNavEntry entry) async {
    final list = entry.list;
    if (list == null || list.isSystem) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除清单'),
          content: Text('确定删除“${list.name}”吗？清单内的任务会保留并移到“全部”。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await widget.controller.store.deleteTodoList(list);
    if (!mounted) {
      return;
    }
    setState(() {
      if (_selectedListId == list.id) {
        _selectedListId = TodoList.inboxId;
      }
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除清单“${list.name}”')));
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
    required this.onDeleteList,
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
  final Future<void> Function(TodoNavEntry entry) onDeleteList;
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
    if (widget.compact) {
      return _CompactTodoDrawerLayout(
        entries: widget.entries,
        selectedEntry: widget.selectedEntry,
        controller: widget.controller,
        syncing: widget.syncing,
        onSelected: widget.onSelected,
        onAddTodo: widget.onAddTodo,
        onAddList: widget.onAddList,
        onDeleteList: widget.onDeleteList,
        onSearch: widget.onSearch,
        onUpdate: widget.onUpdate,
        onSync: widget.onSync,
        onSyncPage: widget.onSyncPage,
        onRefresh: widget.onRefresh,
      );
    }
    return _DesktopTodoShell(
      entries: widget.entries,
      selectedEntry: widget.selectedEntry,
      controller: widget.controller,
      sidebarExpanded: _desktopPaneExpanded,
      syncing: widget.syncing,
      onToggleSidebar: () {
        setState(() => _desktopPaneExpanded = !_desktopPaneExpanded);
      },
      onSelected: widget.onSelected,
      onAddTodo: widget.onAddTodo,
      onAddList: widget.onAddList,
      onDeleteList: widget.onDeleteList,
      onSearch: widget.onSearch,
      onSync: widget.onSync,
      onSyncPage: widget.onSyncPage,
      onRefresh: widget.onRefresh,
    );
  }
}

class _DesktopTodoShell extends StatelessWidget {
  const _DesktopTodoShell({
    required this.entries,
    required this.selectedEntry,
    required this.controller,
    required this.sidebarExpanded,
    required this.syncing,
    required this.onToggleSidebar,
    required this.onSelected,
    required this.onAddTodo,
    required this.onAddList,
    required this.onDeleteList,
    required this.onSearch,
    required this.onSync,
    required this.onSyncPage,
    required this.onRefresh,
  });

  final List<TodoNavEntry> entries;
  final TodoNavEntry selectedEntry;
  final AppController controller;
  final bool sidebarExpanded;
  final bool syncing;
  final VoidCallback onToggleSidebar;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddTodo;
  final VoidCallback onAddList;
  final Future<void> Function(TodoNavEntry entry) onDeleteList;
  final VoidCallback onSearch;
  final VoidCallback? onSync;
  final VoidCallback onSyncPage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return _DesktopWindowFrame(
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: sidebarExpanded ? 288 : 84,
            child: _DesktopSidebar(
              entries: entries,
              selectedEntry: selectedEntry,
              controller: controller,
              expanded: sidebarExpanded,
              syncing: syncing,
              onToggle: onToggleSidebar,
              onSelected: onSelected,
              onAddList: onAddList,
              onDeleteList: onDeleteList,
              onSearch: onSearch,
              onSync: onSync,
              onSyncPage: onSyncPage,
            ),
          ),
          const VerticalDivider(width: 1, color: _appBorderSoft),
          Expanded(
            child: _FluentMainContent(
              entry: selectedEntry,
              controller: controller,
              compact: false,
              syncing: syncing,
              onAddTodo: onAddTodo,
              onSearch: onSearch,
              onSync: onSync,
              onSettings: onSyncPage,
              onRefresh: onRefresh,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopWindowFrame extends StatefulWidget {
  const _DesktopWindowFrame({required this.child});

  final Widget child;

  @override
  State<_DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<_DesktopWindowFrame>
    with window_manager.WindowListener {
  bool _isMaximized = false;

  bool get _showCustomTitleBar => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    if (_showCustomTitleBar) {
      window_manager.windowManager.addListener(this);
      unawaited(_syncMaximizedState());
    }
  }

  @override
  void dispose() {
    if (_showCustomTitleBar) {
      window_manager.windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _isMaximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _isMaximized = false);
    }
  }

  Future<void> _syncMaximizedState() async {
    final maximized = await window_manager.windowManager.isMaximized();
    if (mounted) {
      setState(() => _isMaximized = maximized);
    }
  }

  Future<void> _toggleMaximize() async {
    final maximized = await window_manager.windowManager.isMaximized();
    if (maximized) {
      await window_manager.windowManager.unmaximize();
    } else {
      await window_manager.windowManager.maximize();
    }
    await _syncMaximizedState();
  }

  @override
  Widget build(BuildContext context) {
    const radius = 0.0;
    const padding = EdgeInsets.zero;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _appSurface,
          border: Border.all(
            color: _showCustomTitleBar && _isMaximized
                ? Colors.transparent
                : _appBorder,
          ),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Column(
            children: [
              if (_showCustomTitleBar)
                _DesktopWindowTitleBar(
                  isMaximized: _isMaximized,
                  onToggleMaximize: _toggleMaximize,
                ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopWindowTitleBar extends StatelessWidget {
  const _DesktopWindowTitleBar({
    required this.isMaximized,
    required this.onToggleMaximize,
  });

  final bool isMaximized;
  final Future<void> Function() onToggleMaximize;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Color.lerp(_appSurface, _appSurfaceWarm, 0.18),
        border: const Border(bottom: BorderSide(color: _appBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: window_manager.DragToMoveArea(
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      _AppMark(size: 30),
                      const SizedBox(width: 10),
                      const Text(
                        'MyTodo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _appForeground,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _WindowControlButton(
            tooltip: '最小化',
            icon: Icons.minimize,
            onTap: () => unawaited(window_manager.windowManager.minimize()),
          ),
          _WindowControlButton(
            tooltip: isMaximized ? '还原' : '最大化',
            icon: isMaximized ? Icons.filter_none : Icons.crop_square,
            onTap: () => unawaited(onToggleMaximize()),
          ),
          _WindowControlButton(
            tooltip: '关闭',
            icon: Icons.close,
            danger: true,
            onTap: () => unawaited(window_manager.windowManager.close()),
          ),
        ],
      ),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final hoveredColor = widget.danger ? _appDanger : _appSurfaceWarm;
    final iconColor = _hovering
        ? widget.danger
              ? _appAccentOn
              : _appForeground
        : _appMeta;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Material(
          color: _hovering ? hoveredColor : Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Container(
              width: 46,
              height: 44,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: _appBorder.withValues(alpha: 0.72)),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(widget.icon, size: 15, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/mytodo_taskbar.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.entries,
    required this.selectedEntry,
    required this.controller,
    required this.expanded,
    required this.syncing,
    required this.onToggle,
    required this.onSelected,
    required this.onAddList,
    required this.onDeleteList,
    required this.onSearch,
    required this.onSync,
    required this.onSyncPage,
  });

  final List<TodoNavEntry> entries;
  final TodoNavEntry selectedEntry;
  final AppController controller;
  final bool expanded;
  final bool syncing;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddList;
  final Future<void> Function(TodoNavEntry entry) onDeleteList;
  final VoidCallback onSearch;
  final VoidCallback? onSync;
  final VoidCallback onSyncPage;

  @override
  Widget build(BuildContext context) {
    final smartEntries = entries.where((entry) => entry.isVirtual).toList();
    final listEntries = entries.where((entry) => !entry.isVirtual).toList();
    return Container(
      color: Color.lerp(_appSurface, _appSurfaceWarm, 0.44),
      padding: expanded
          ? const EdgeInsets.all(24)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DesktopBrandRow(expanded: expanded, onToggle: onToggle),
          SizedBox(height: expanded ? 18 : 14),
          _DesktopSearchBox(expanded: expanded, onTap: onSearch),
          SizedBox(height: expanded ? 18 : 14),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (expanded) const _NavSectionTitle('智能视图'),
                for (final entry in smartEntries)
                  _DesktopNavTile(
                    entry: entry,
                    selected: entry.id == selectedEntry.id,
                    count: controller.store.activeCountFor(entry.id),
                    expanded: expanded,
                    onTap: () => onSelected(entry.id),
                  ),
                SizedBox(height: expanded ? 16 : 8),
                if (expanded)
                  Row(
                    children: [
                      const Expanded(child: _NavSectionTitle('清单')),
                      IconButton(
                        tooltip: '添加清单',
                        onPressed: onAddList,
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                      ),
                    ],
                  ),
                for (final entry in listEntries)
                  _DesktopNavTile(
                    entry: entry,
                    selected: entry.id == selectedEntry.id,
                    count: controller.store.activeCountFor(entry.id),
                    expanded: expanded,
                    onTap: () => onSelected(entry.id),
                    onDelete: entry.isCustomList
                        ? () => unawaited(onDeleteList(entry))
                        : null,
                  ),
                SizedBox(height: expanded ? 16 : 8),
                if (expanded) const _NavSectionTitle('系统'),
                _DesktopActionNavTile(
                  icon: Icons.settings_outlined,
                  label: '设置',
                  trailing: _appVersionLabel,
                  expanded: expanded,
                  onTap: onSyncPage,
                ),
              ],
            ),
          ),
          _DesktopSyncCard(
            expanded: expanded,
            syncing: syncing,
            onSync: onSync,
          ),
        ],
      ),
    );
  }
}

class _DesktopBrandRow extends StatelessWidget {
  const _DesktopBrandRow({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '展开菜单',
            onPressed: onToggle,
            icon: const Icon(Icons.menu),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Expanded(
          child: Text(
            'MyTodo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _appForeground,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: expanded ? '收起侧边栏' : '展开侧边栏',
          onPressed: onToggle,
          icon: Icon(expanded ? Icons.menu_open : Icons.menu),
        ),
      ],
    );
  }
}

class _DesktopSearchBox extends StatelessWidget {
  const _DesktopSearchBox({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
          decoration: BoxDecoration(
            color: _appSurface,
            border: Border.all(color: _appBorderSoft),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _appSurfaceWarm.withValues(alpha: 0.40),
                blurRadius: 0,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              const Icon(Icons.search, size: 18, color: _appMeta),
              if (expanded) ...[
                const SizedBox(width: 10),
                Text(
                  '搜索任务、笔记或历史',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: _appMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSectionTitle extends StatelessWidget {
  const _NavSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _appMeta,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DesktopNavTile extends StatelessWidget {
  const _DesktopNavTile({
    required this.entry,
    required this.selected,
    required this.count,
    required this.expanded,
    required this.onTap,
    this.onDelete,
  });

  final TodoNavEntry entry;
  final bool selected;
  final int count;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? _appForeground : _appMuted;
    final tile = Material(
      color: selected
          ? Color.lerp(_appSurface, _appSurfaceWarm, 0.72)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: expanded ? double.infinity : 46,
          constraints: const BoxConstraints(minHeight: 42),
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 10 : 8,
            vertical: 7,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    entry.icon,
                    size: expanded ? 19 : 20,
                    color: selected ? _appAccent : _appMuted,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (count > 0) _SidebarCountBadge(count: count),
                    if (onDelete != null)
                      PopupMenuButton<_ListMenuAction>(
                        tooltip: '清单操作',
                        icon: const Icon(Icons.more_horiz, size: 18),
                        onSelected: (action) {
                          if (action == _ListMenuAction.delete) {
                            onDelete?.call();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _ListMenuAction.delete,
                            child: Text('删除清单'),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
              if (!expanded && count > 0)
                Positioned(
                  top: -3,
                  right: -5,
                  child: _CollapsedCountBadge(count: count),
                ),
            ],
          ),
        ),
      ),
    );
    return Tooltip(
      message: expanded ? '' : entry.name,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Align(
          alignment: expanded ? Alignment.centerLeft : Alignment.center,
          child: tile,
        ),
      ),
    );
  }
}

class _CollapsedCountBadge extends StatelessWidget {
  const _CollapsedCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _appSurface,
        border: Border.all(color: _appBorderSoft),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: _appMeta,
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DesktopActionNavTile extends StatelessWidget {
  const _DesktopActionNavTile({
    required this.icon,
    required this.label,
    required this.trailing,
    required this.expanded,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String trailing;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: expanded ? double.infinity : 46,
          constraints: const BoxConstraints(minHeight: 42),
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 10 : 8,
            vertical: 7,
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(icon, size: expanded ? 19 : 20, color: _appMeta),
              if (expanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _appMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  trailing,
                  style: const TextStyle(
                    color: _appMeta,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Tooltip(
      message: expanded ? '' : label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Align(
          alignment: expanded ? Alignment.centerLeft : Alignment.center,
          child: tile,
        ),
      ),
    );
  }
}

class _SidebarCountBadge extends StatelessWidget {
  const _SidebarCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _appSurfaceWarm.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count.toString(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _appMeta,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DesktopSyncCard extends StatelessWidget {
  const _DesktopSyncCard({
    required this.expanded,
    required this.syncing,
    required this.onSync,
  });

  final bool expanded;
  final bool syncing;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _appSurface,
          border: Border.all(color: _appBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Tooltip(
          message: syncing ? '同步中' : '立即同步',
          child: FilledButton(
            onPressed: onSync,
            style: FilledButton.styleFrom(
              minimumSize: const Size(42, 42),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: syncing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync, size: 18),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _appSurface,
        border: Border.all(color: _appBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '远程同步',
                  style: TextStyle(
                    color: _appForeground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(label: syncing ? '同步中' : '就绪', active: !syncing),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '本地优先保存，联网后自动推送到 Supabase 空间。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _appMuted),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onSync,
            icon: syncing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync, size: 18),
            label: Text(syncing ? '同步中' : '立即同步'),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? _appSuccess : _appMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
    required this.onDeleteList,
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
  final Future<void> Function(TodoNavEntry entry) onDeleteList;
  final VoidCallback onSearch;
  final VoidCallback onUpdate;
  final VoidCallback? onSync;
  final VoidCallback onSyncPage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final drawerWidth = math.min(
      MediaQuery.sizeOf(context).width * 0.82,
      280.0,
    );
    return Scaffold(
      backgroundColor: _appBackground,
      drawer: Drawer(
        width: drawerWidth,
        backgroundColor: _appBackground,
        shape: const RoundedRectangleBorder(),
        child: SafeArea(
          child: _CompactNavigationDrawer(
            entries: entries,
            selectedEntry: selectedEntry,
            controller: controller,
            onSelected: onSelected,
            onAddTodo: onAddTodo,
            onAddList: onAddList,
            onDeleteList: onDeleteList,
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
          return Stack(
            children: [
              _FluentMainContent(
                entry: selectedEntry,
                controller: controller,
                compact: true,
                syncing: syncing,
                onAddTodo: onAddTodo,
                onSearch: onSearch,
                onSync: onSync,
                onSettings: onSyncPage,
                onRefresh: onRefresh,
                onOpenNavigation: Scaffold.of(context).openDrawer,
              ),
              Positioned(
                right: 24,
                bottom: 92,
                child: _MobileFab(onTap: onAddTodo),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: _MobileBottomNav(
                  entries: entries.where((entry) => entry.isVirtual).toList(),
                  selectedEntry: selectedEntry,
                  onSelected: onSelected,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MobileFab extends StatelessWidget {
  const _MobileFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'mobile-add-todo',
      onPressed: onTap,
      backgroundColor: _appAccent,
      foregroundColor: _appAccentOn,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: const Icon(Icons.add),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.entries,
    required this.selectedEntry,
    required this.onSelected,
  });

  final List<TodoNavEntry> entries;
  final TodoNavEntry selectedEntry;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final visible = entries.take(3).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _appSurface.withValues(alpha: 0.96),
        border: Border.all(color: _appBorder),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _appForeground.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            for (final entry in visible)
              Expanded(
                child: _MobileBottomNavItem(
                  entry: entry,
                  selected: entry.id == selectedEntry.id,
                  onTap: () => onSelected(entry.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileBottomNavItem extends StatelessWidget {
  const _MobileBottomNavItem({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final TodoNavEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _appAccent : _appMuted;
    return Material(
      color: selected ? _appAccent.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(entry.icon, size: 18, color: color),
              const SizedBox(height: 3),
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
    required this.onDeleteList,
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
  final Future<void> Function(TodoNavEntry entry) onDeleteList;
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
              color: _appForeground,
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
                  onDelete: entry.isCustomList
                      ? () {
                          Navigator.of(context).pop();
                          unawaited(onDeleteList(entry));
                        }
                      : null,
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
          label: '设置',
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
    this.onDelete,
  });

  final TodoNavEntry entry;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? _appAccent : _appForegroundSoft;
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
        trailing: count > 0 || onDelete != null
            ? _CompactNavigationTileActions(count: count, onDelete: onDelete)
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _CompactNavigationTileActions extends StatelessWidget {
  const _CompactNavigationTileActions({required this.count, this.onDelete});

  final int count;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count > 0) _DrawerCountBadge(count: count),
        if (count > 0 && onDelete != null) const SizedBox(width: 4),
        if (onDelete != null)
          PopupMenuButton<_ListMenuAction>(
            tooltip: '清单操作',
            icon: const Icon(Icons.more_horiz, size: 20),
            onSelected: (action) {
              switch (action) {
                case _ListMenuAction.delete:
                  onDelete?.call();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ListMenuAction.delete,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('删除清单'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

enum _ListMenuAction { delete }

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
      leading: Icon(icon, color: _appAccent),
      title: Text(
        label,
        style: const TextStyle(
          color: _appForeground,
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
          color: _appAccentOn,
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
    required this.onSync,
    required this.onSettings,
    required this.onRefresh,
    this.onOpenNavigation,
  });

  final TodoNavEntry entry;
  final AppController controller;
  final bool compact;
  final bool syncing;
  final VoidCallback onAddTodo;
  final VoidCallback onSearch;
  final VoidCallback? onSync;
  final VoidCallback onSettings;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenNavigation;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (onOpenNavigation != null)
          _MobileNavigationBar(
            entry: entry,
            onOpenNavigation: onOpenNavigation!,
            syncing: syncing,
            onSearch: onSearch,
            onSync: onSync,
            onSettings: onSettings,
          ),
        Expanded(
          child: _TodoContentPage(
            entry: entry,
            controller: controller,
            onAddTodo: onAddTodo,
            onSearch: onSearch,
            onRefresh: onRefresh,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _MobileNavigationBar extends StatelessWidget {
  const _MobileNavigationBar({
    required this.entry,
    required this.onOpenNavigation,
    required this.syncing,
    required this.onSearch,
    required this.onSync,
    required this.onSettings,
  });

  final TodoNavEntry entry;
  final VoidCallback onOpenNavigation;
  final bool syncing;
  final VoidCallback onSearch;
  final VoidCallback? onSync;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(color: _appBackground),
      child: Row(
        children: [
          _TopIconButton(
            tooltip: '打开侧边栏',
            icon: Icons.menu,
            onTap: onOpenNavigation,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今天',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _appAccent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _appForeground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          _TopIconButton(tooltip: '搜索', icon: Icons.search, onTap: onSearch),
          _TopIconButton(
            tooltip: syncing ? '同步中' : '同步',
            icon: Icons.sync,
            onTap: onSync,
          ),
          _TopIconButton(
            tooltip: '设置',
            icon: Icons.settings_outlined,
            onTap: onSettings,
          ),
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
        color: _appForeground,
      ),
    );
  }
}

class _TodoContentPage extends StatefulWidget {
  const _TodoContentPage({
    required this.entry,
    required this.controller,
    required this.onAddTodo,
    required this.onSearch,
    this.onRefresh,
    this.compact = false,
  });

  final TodoNavEntry entry;
  final AppController controller;
  final VoidCallback onAddTodo;
  final VoidCallback onSearch;
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
      compact: widget.compact,
    );
    return Padding(
      padding: widget.compact
          ? const EdgeInsets.fromLTRB(16, 0, 16, 0)
          : const EdgeInsets.fromLTRB(44, 42, 44, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileSummaryCard(entry: widget.entry, todos: todos),
                const SizedBox(height: 4),
              ],
            )
          else
            _DesktopContentToolbar(
              entry: widget.entry,
              onAddTodo: widget.onAddTodo,
              onSearch: widget.onSearch,
            ),
          _TodoOverview(
            todos: todos,
            selectedFilter: _filter,
            compact: widget.compact,
            onFilterChanged: (filter) {
              setState(() => _filter = filter);
            },
          ),
          SizedBox(height: widget.compact ? 10 : 18),
          Expanded(
            child: widget.onRefresh == null
                ? list
                : RefreshIndicator(onRefresh: widget.onRefresh!, child: list),
          ),
        ],
      ),
    );
  }

  String get _emptyLabel {
    return switch (_filter) {
      TodoViewFilter.active => '暂无当前任务',
      TodoViewFilter.overdue => '没有逾期任务',
      TodoViewFilter.completed => '还没有已完成任务',
      TodoViewFilter.all => '暂无任务',
    };
  }
}

class _DesktopContentToolbar extends StatelessWidget {
  const _DesktopContentToolbar({
    required this.entry,
    required this.onAddTodo,
    required this.onSearch,
  });

  final TodoNavEntry entry;
  final VoidCallback onAddTodo;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 42,
                    color: _appForeground,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  entry.isVirtual
                      ? subtitleForView(entry.id)
                      : '按完成状态查看和处理当前清单任务',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: _appMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _ToolbarIconButton(
            tooltip: '历史搜索',
            icon: Icons.history,
            onTap: onSearch,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onAddTodo,
            icon: const Icon(Icons.add),
            label: const Text('添加任务'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
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
      child: Material(
        color: _appSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              border: Border.all(color: _appBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _appForeground, size: 20),
          ),
        ),
      ),
    );
  }
}

class _MobileSummaryCard extends StatelessWidget {
  const _MobileSummaryCard({required this.entry, required this.todos});

  final TodoNavEntry entry;
  final List<TodoItem> todos;

  @override
  Widget build(BuildContext context) {
    final counts = countTodosByView(
      todos,
      DateTime.now().millisecondsSinceEpoch,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _appSurface,
        border: Border.all(color: _appBorder),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.id == TodoList.viewMyDayId ? '保持今天可完成' : entry.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _appForeground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '当前 ${counts.active}，逾期 ${counts.overdue}，完成 ${counts.completed}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: _appMuted),
                ),
              ],
            ),
          ),
          const _StatusPill(label: '本地', active: true),
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
      TodoViewFilter.all => '暂无任务',
    };
  }
}

class _TodoOverview extends StatelessWidget {
  const _TodoOverview({
    required this.todos,
    required this.selectedFilter,
    required this.onFilterChanged,
    this.compact = false,
  });

  final List<TodoItem> todos;
  final TodoViewFilter selectedFilter;
  final ValueChanged<TodoViewFilter> onFilterChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final counts = countTodosByView(todos, now);
    final tiles = [
      _OverviewTile(
        label: '当前',
        value: counts.active,
        selected: selectedFilter == TodoViewFilter.active,
        color: Theme.of(context).colorScheme.primary,
        compact: compact,
        onTap: () => onFilterChanged(TodoViewFilter.active),
      ),
      _OverviewTile(
        label: '逾期',
        value: counts.overdue,
        selected: selectedFilter == TodoViewFilter.overdue,
        color: Theme.of(context).colorScheme.error,
        compact: compact,
        onTap: () => onFilterChanged(TodoViewFilter.overdue),
      ),
      _OverviewTile(
        label: '完成',
        value: counts.completed,
        selected: selectedFilter == TodoViewFilter.completed,
        color: _appSuccess,
        compact: compact,
        onTap: () => onFilterChanged(TodoViewFilter.completed),
      ),
    ];
    if (!compact) {
      tiles.add(
        _OverviewTile(
          label: '全部',
          value: todos.length,
          selected: selectedFilter == TodoViewFilter.all,
          color: _appForegroundSoft,
          compact: compact,
          onTap: () => onFilterChanged(TodoViewFilter.all),
        ),
      );
    }
    if (compact) {
      return Row(
        children: [
          for (var index = 0; index < tiles.length; index++) ...[
            Expanded(child: tiles[index]),
            if (index != tiles.length - 1) const SizedBox(width: 8),
          ],
        ],
      );
    }
    return Wrap(spacing: 10, runSpacing: 10, children: tiles);
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final int value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? Color.lerp(_appSurface, _appSurfaceWarm, 0.66)
        : _appSurface;
    const borderColor = _appBorderSoft;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: compact ? null : null,
          constraints: BoxConstraints(minHeight: compact ? 40 : 44),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: compact
              ? Center(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected ? _appForeground : _appMuted,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: selected ? _appForeground : _appMuted,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      value.toString(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: selected ? _appForeground : color,
                        fontWeight: FontWeight.w900,
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
    this.compact = false,
    this.onAddTodo,
    this.onReorder,
  });

  final List<TodoItem> todos;
  final AppController controller;
  final bool historyMode;
  final String emptyLabel;
  final bool shrinkWrap;
  final bool compact;
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
              padding: EdgeInsets.only(bottom: compact ? 168 : 96),
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
        padding: EdgeInsets.only(bottom: compact ? 168 : 96),
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
      padding: EdgeInsets.only(
        bottom: historyMode
            ? 16
            : compact
            ? 168
            : 96,
      ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _appAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.checklist, size: 34, color: _appAccent),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _appForeground,
                fontWeight: FontWeight.w800,
              ),
            ),
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
        ? Color.lerp(_appSurface, _appSurfaceWarm, 0.84)!
        : _appSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: todo.deleted
            ? null
            : () => _showTodoEditorDialog(
                context,
                controller: controller,
                todo: todo,
                title: '编辑任务',
              ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _appForeground.withValues(alpha: 0.04),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (todo.deleted)
                SizedBox.square(
                  dimension: 40,
                  child: Icon(Icons.history, color: scheme.error),
                )
              else
                _TaskCheckButton(
                  completed: todo.completed,
                  onChanged: (value) {
                    controller.store.setCompleted(todo, value);
                  },
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        decoration: inactive
                            ? TextDecoration.lineThrough
                            : null,
                        color: inactive ? _appMuted : _appForeground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _TodoMetadata(todo: todo, historyMode: historyMode),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!todo.deleted)
                ImportantToggleButton(
                  important: todo.important,
                  onPressed: () {
                    controller.store.setImportant(todo, !todo.important);
                  },
                ),
              _TodoTileActions(
                todo: todo,
                historyMode: historyMode,
                reorderIndex: reorderIndex,
                onDelete: () => controller.store.deleteTodo(todo),
                onRestore: () => controller.store.restoreTodo(todo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCheckButton extends StatelessWidget {
  const _TaskCheckButton({required this.completed, required this.onChanged});

  final bool completed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: completed ? '恢复未完成' : '标记完成',
      child: InkResponse(
        onTap: () => onChanged(!completed),
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: completed ? _appSuccess : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: completed
                  ? _appSuccess
                  : _appMuted.withValues(alpha: 0.55),
              width: 2,
            ),
          ),
          child: Icon(
            Icons.check,
            size: 18,
            color: completed ? _appAccentOn : Colors.transparent,
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
  final now = DateTime.now().millisecondsSinceEpoch;
  if (todo.deleted) {
    return _appDanger.withValues(alpha: 0.32);
  }
  if (!todo.completed && isTodoOverdue(todo, now)) {
    return _appDanger.withValues(alpha: 0.5);
  }
  if (todo.completed) {
    return _appBorder.withValues(alpha: 0.7);
  }
  return _appBorder;
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
    if (todo.sourceType == TodoSource.recurring) {
      chips.add(const _MetaChip(icon: Icons.repeat, label: '每天'));
    }
    if (todo.notes.trim().isNotEmpty) {
      chips.add(const _MetaChip(icon: Icons.notes_outlined, label: '有笔记'));
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
          color: todo.completed ? _appSuccess : null,
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
    final effectiveColor = color ?? _appMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.transparent,
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
  final notesController = TextEditingController(text: todo?.notes ?? '');
  final lists = controller.store.lists;
  var selectedListId = todo?.listId ?? initialListId;
  if (!lists.any((list) => list.id == selectedListId)) {
    selectedListId = lists.any((list) => list.id == TodoList.inboxId)
        ? TodoList.inboxId
        : lists.isEmpty
        ? TodoList.inboxId
        : lists.first.id;
  }
  var repeat = todo == null ? _TodoRepeat.none : _TodoRepeat.none;
  var dueAt = todo?.dueAt ?? initialDueAt;
  var reminderAt = todo?.reminderAt;
  _TodoEditorResult? result;
  final editorTitle = todo == null ? title : '编辑任务';

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

  Widget buildContent({
    required BuildContext dialogContext,
    required void Function(void Function()) setDialogState,
    required Future<void> Function() save,
  }) {
    return _TodoEditorContent(
      titleController: titleController,
      notesController: notesController,
      lists: lists,
      selectedListId: selectedListId,
      repeat: repeat,
      showRepeat: todo == null,
      dueAt: dueAt,
      reminderAt: reminderAt,
      onSaveTitle: save,
      onListChanged: (value) => setDialogState(() => selectedListId = value),
      onRepeatChanged: (value) {
        setDialogState(() {
          repeat = value;
          if (repeat == _TodoRepeat.daily) {
            dueAt = null;
            reminderAt = null;
          }
        });
      },
      onPickDueAt: repeat == _TodoRepeat.daily
          ? null
          : () => pickDateTime(
              dialogContext: dialogContext,
              setDialogState: setDialogState,
              currentValue: dueAt,
              onChanged: (value) => dueAt = value,
            ),
      onClearDueAt: dueAt == null || repeat == _TodoRepeat.daily
          ? null
          : () => setDialogState(() => dueAt = null),
      onPickReminderAt: repeat == _TodoRepeat.daily
          ? null
          : () => pickDateTime(
              dialogContext: dialogContext,
              setDialogState: setDialogState,
              currentValue: reminderAt,
              onChanged: (value) => reminderAt = value,
            ),
      onClearReminderAt: reminderAt == null || repeat == _TodoRepeat.daily
          ? null
          : () => setDialogState(() => reminderAt = null),
    );
  }

  Future<void> Function([_TodoEditorResult?]) buildClose(
    BuildContext dialogContext,
  ) {
    return ([_TodoEditorResult? result]) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop(result);
      }
    };
  }

  Future<void> Function() buildSave(
    Future<void> Function([_TodoEditorResult?]) close,
  ) {
    return () async {
      final trimmed = titleController.text.trim();
      if (trimmed.isEmpty) {
        return;
      }
      await close(
        _TodoEditorResult(
          title: trimmed,
          listId: selectedListId,
          repeat: repeat,
          dueAt: dueAt,
          reminderAt: reminderAt,
          notes: notesController.text,
        ),
      );
    };
  }

  try {
    final compactEditor =
        MediaQuery.sizeOf(context).width < 640 ||
        Platform.isAndroid ||
        Platform.isIOS;
    if (compactEditor) {
      result = await showModalBottomSheet<_TodoEditorResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        requestFocus: _shouldAutofocusEditor,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final close = buildClose(dialogContext);
              final save = buildSave(close);
              final size = MediaQuery.sizeOf(dialogContext);
              return PopScope<_TodoEditorResult>(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) {
                    close();
                  }
                },
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Material(
                      color: _appSurface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 640,
                          maxHeight: size.height * 0.94,
                        ),
                        child: Theme(
                          data: _todoEditorTheme(dialogContext),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  22,
                                  14,
                                  10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        editorTitle,
                                        style: Theme.of(dialogContext)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              color: _appForeground,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '关闭',
                                      onPressed: () => close(),
                                      icon: const Icon(Icons.close),
                                      color: _appMuted,
                                    ),
                                  ],
                                ),
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    14,
                                    24,
                                    20,
                                  ),
                                  child: buildContent(
                                    dialogContext: dialogContext,
                                    setDialogState: setDialogState,
                                    save: save,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  8,
                                  24,
                                  24,
                                ),
                                child: Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => close(),
                                      child: const Text('取消'),
                                    ),
                                    const Spacer(),
                                    FilledButton(
                                      onPressed: save,
                                      child: const Text('保存任务'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } else {
      result = await showGeneralDialog<_TodoEditorResult>(
        context: context,
        barrierDismissible: false,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: _appForeground.withValues(alpha: 0.18),
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final close = buildClose(dialogContext);
              final save = buildSave(close);
              final size = MediaQuery.sizeOf(dialogContext);
              final panelWidth = math.min(
                460.0,
                math.max(320.0, size.width - 24),
              );
              final panelHeight = math.max(0.0, size.height - 24);
              return PopScope<_TodoEditorResult>(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) {
                    close();
                  }
                },
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Theme(
                        data: _todoEditorTheme(dialogContext),
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: panelWidth,
                            height: panelHeight,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: _appSurface,
                              border: Border.all(color: _appBorder),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  blurRadius: 34,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        editorTitle,
                                        style: Theme.of(dialogContext)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              color: _appForeground,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '关闭',
                                      onPressed: () => close(),
                                      icon: const Icon(Icons.close),
                                      color: _appMuted,
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      2,
                                      14,
                                      2,
                                      14,
                                    ),
                                    child: buildContent(
                                      dialogContext: dialogContext,
                                      setDialogState: setDialogState,
                                      save: save,
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => close(),
                                      child: const Text('取消'),
                                    ),
                                    const Spacer(),
                                    FilledButton(
                                      onPressed: save,
                                      child: const Text('保存任务'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          );
        },
      );
    }
  } finally {
    titleController.dispose();
    notesController.dispose();
  }
  if (result == null) {
    return;
  }
  if (todo == null) {
    if (result.repeat == _TodoRepeat.daily) {
      await controller.store.createRecurringTemplate(
        result.title,
        listId: result.listId,
        notes: result.notes,
      );
    } else {
      await controller.store.createTodo(
        result.title,
        listId: result.listId,
        dueAt: result.dueAt,
        reminderAt: result.reminderAt,
        important: initialImportant,
        notes: result.notes,
      );
    }
  } else {
    await controller.store.updateTodo(
      todo,
      title: result.title,
      dueAt: result.dueAt,
      reminderAt: result.reminderAt,
      listId: result.listId,
      notes: result.notes,
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

ThemeData _todoEditorTheme(BuildContext context) {
  final base = Theme.of(context);
  final scheme = base.colorScheme.copyWith(
    primary: _appAccent,
    surface: _appSurface,
    onSurface: _appForeground,
    onSurfaceVariant: _appMuted,
    outline: _appBorder,
    outlineVariant: _appBorder,
    error: _appDanger,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: _appBorder),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: _appSurface,
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: _appSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _appSurface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _appAccent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _appDanger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _appDanger, width: 1.6),
      ),
      labelStyle: const TextStyle(color: _appMuted),
      floatingLabelStyle: const TextStyle(
        color: _appAccent,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: TextStyle(color: _appMuted.withValues(alpha: 0.68)),
      iconColor: _appMuted,
      prefixIconColor: _appMuted,
      suffixIconColor: _appForeground,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _appForeground,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _appAccent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _appBorder,
        disabledForegroundColor: _appMuted,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        minimumSize: const Size(116, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

class _TodoEditorContent extends StatelessWidget {
  const _TodoEditorContent({
    required this.titleController,
    required this.notesController,
    required this.lists,
    required this.selectedListId,
    required this.repeat,
    required this.showRepeat,
    required this.dueAt,
    required this.reminderAt,
    required this.onSaveTitle,
    required this.onListChanged,
    required this.onRepeatChanged,
    required this.onPickDueAt,
    required this.onClearDueAt,
    required this.onPickReminderAt,
    required this.onClearReminderAt,
  });

  final TextEditingController titleController;
  final TextEditingController notesController;
  final List<TodoList> lists;
  final String selectedListId;
  final _TodoRepeat repeat;
  final bool showRepeat;
  final int? dueAt;
  final int? reminderAt;
  final Future<void> Function() onSaveTitle;
  final ValueChanged<String> onListChanged;
  final ValueChanged<_TodoRepeat> onRepeatChanged;
  final VoidCallback? onPickDueAt;
  final VoidCallback? onClearDueAt;
  final VoidCallback? onPickReminderAt;
  final VoidCallback? onClearReminderAt;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EditorFieldLabel('任务标题'),
        TextField(
          controller: titleController,
          autofocus: _shouldAutofocusEditor,
          textInputAction: TextInputAction.done,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _appForeground,
            fontWeight: FontWeight.w500,
          ),
          decoration: const InputDecoration(hintText: '输入任务标题'),
          onSubmitted: (_) => onSaveTitle(),
        ),
        const SizedBox(height: 18),
        const _EditorFieldLabel('所属清单'),
        DropdownButtonFormField<String>(
          initialValue: selectedListId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          decoration: const InputDecoration(),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _appForeground,
            fontWeight: FontWeight.w500,
          ),
          dropdownColor: _appSurface,
          items: [
            for (final list in lists)
              DropdownMenuItem(
                value: list.id,
                child: Text(
                  list.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              onListChanged(value);
            }
          },
        ),
        if (showRepeat) ...[
          const SizedBox(height: 18),
          const _EditorFieldLabel('重复'),
          DropdownButtonFormField<_TodoRepeat>(
            initialValue: repeat,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down),
            decoration: const InputDecoration(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: _appForeground,
              fontWeight: FontWeight.w500,
            ),
            dropdownColor: _appSurface,
            items: const [
              DropdownMenuItem(value: _TodoRepeat.none, child: Text('不重复')),
              DropdownMenuItem(value: _TodoRepeat.daily, child: Text('每天')),
            ],
            onChanged: (value) {
              if (value != null) {
                onRepeatChanged(value);
              }
            },
          ),
        ],
        const SizedBox(height: 18),
        const _EditorFieldLabel('截止日期'),
        _DateTimeField(
          value: dueAt,
          emptyLabel: '年 /月/日  --:--',
          icon: Icons.calendar_today_outlined,
          enabled: repeat != _TodoRepeat.daily,
          onPick: onPickDueAt,
          onClear: onClearDueAt,
        ),
        const SizedBox(height: 18),
        const _EditorFieldLabel('提醒时间'),
        _DateTimeField(
          value: reminderAt,
          emptyLabel: '年 /月/日  --:--',
          icon: Icons.calendar_today_outlined,
          enabled: repeat != _TodoRepeat.daily,
          onPick: onPickReminderAt,
          onClear: onClearReminderAt,
        ),
        const SizedBox(height: 18),
        const _EditorFieldLabel('笔记'),
        TextField(
          controller: notesController,
          minLines: 6,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: _appForeground, height: 1.45),
          decoration: const InputDecoration(
            hintText: '记录步骤、链接、代码片段或补充说明',
            alignLabelWithHint: true,
            contentPadding: EdgeInsets.fromLTRB(16, 16, 16, 16),
          ),
        ),
      ],
    );
  }
}

class _EditorFieldLabel extends StatelessWidget {
  const _EditorFieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: _appMuted,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

bool get _shouldAutofocusEditor => !(Platform.isAndroid || Platform.isIOS);

class _TodoEditorResult {
  const _TodoEditorResult({
    required this.title,
    required this.listId,
    required this.repeat,
    required this.dueAt,
    required this.reminderAt,
    required this.notes,
  });

  final String title;
  final String listId;
  final _TodoRepeat repeat;
  final int? dueAt;
  final int? reminderAt;
  final String notes;
}

enum _TodoRepeat { none, daily }

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
    required this.value,
    required this.emptyLabel,
    required this.icon,
    required this.onPick,
    required this.onClear,
    this.enabled = true,
  });

  final int? value;
  final String emptyLabel;
  final IconData icon;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? _appForeground
        : _appMuted.withValues(alpha: 0.48);
    final borderColor = enabled
        ? _appBorder
        : _appBorder.withValues(alpha: 0.6);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPick : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _appSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value == null ? emptyLabel : _formatDateTime(value!),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: !enabled
                        ? foreground
                        : value == null
                        ? _appForeground.withValues(alpha: 0.72)
                        : _appForeground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (onClear == null)
                Icon(icon, color: foreground, size: 22)
              else
                IconButton(
                  tooltip: '清除',
                  onPressed: onClear,
                  color: _appMuted,
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
          appBar: AppBar(title: const Text('设置')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SyncSection(
                    title: '关于 MyTodo',
                    icon: Icons.info_outline,
                    children: const [
                      Text('本地优先保存，联网后同步到 Supabase 空间。'),
                      SizedBox(height: 8),
                      Text('Windows / Android 同步版'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SyncSection(
                    title: '软件更新',
                    icon: Icons.system_update_alt,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('MyTodo $_appVersionLabel · 稳定版通道'),
                          ),
                          const _StatusPill(label: '稳定版', active: true),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: _openUpdatePage,
                          icon: const Icon(Icons.sync),
                          label: const Text('检查更新'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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

  Future<void> _openUpdatePage() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const UpdatePage()));
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
    final enabledColor = config.enabled ? _appSuccess : scheme.onSurfaceVariant;
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
        _SyncStatusPill(text: controller.supabaseSync.status),
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

class _SyncStatusPill extends StatelessWidget {
  const _SyncStatusPill({required this.text});

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
