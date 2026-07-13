import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart' as window_manager;

import 'src/app_controller.dart';
import 'src/data/todo_models.dart';
import 'src/data/savings_models.dart';
import 'src/desktop/windows_tray.dart';
import 'src/search/history_search.dart';
import 'src/sync/supabase_sync_service.dart';
import 'src/ui/theme/app_theme.dart';
import 'src/ui/nav_views.dart';
import 'src/ui/important_toggle_button.dart';
import 'src/ui/reorder_items.dart';
import 'src/ui/todo_filter_tab_content.dart';
import 'src/ui/todo_view_filter.dart';
import 'src/ui/todo_editor_delete_section.dart';
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
const Color _appWarn = Color(0xFFEAB308);
const Color _appDanger = Color(0xFFB53333);
const Color _appSuccess = Color(0xFF17A34A);
const String _appVersionLabel = 'v1.5.1';
const String _appBuildLabel = '构建 2026.07.13';
const String _appDistributionLabel = 'Windows / Android 同步版';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: _appBackground,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: _appBackground,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
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

  Future<void> _showSettingsSurface(BuildContext context) async {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760;
    if (compact) {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: _appSurface,
        barrierColor: _appForeground.withValues(alpha: 0.18),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        isScrollControlled: true,
        builder: (sheetContext) {
          return PopScope(
            canPop: true,
            child: DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return _SettingsSheet(
                  scrollController: scrollController,
                  controller: widget.controller,
                  onCheckUpdate: _openUpdatePage,
                  onSaveSyncConfig: _saveSyncConfig,
                  onSyncRemote: _syncRemote,
                  onTestConnection: _testSupabase,
                );
              },
            ),
          );
        },
      );
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close settings',
      barrierColor: _appForeground.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, _) {
        final panelWidth = math.min(500.0, math.max(360.0, size.width - 24));
        final panelHeight = math.max(0.0, size.height - 24);
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: panelWidth,
                  height: panelHeight,
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
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 2),
                                  child: _KickerText('设置'),
                                ),
                                Text(
                                  '设置与同步',
                                  style: Theme.of(dialogContext)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: _appForeground,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close),
                            color: _appMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _SettingsSurface(
                            controller: widget.controller,
                            onCheckUpdate: () {
                              Navigator.of(dialogContext).pop();
                              unawaited(_openUpdatePage());
                            },
                            onSaveSyncConfig: _saveSyncConfig,
                            onSyncRemote: () async {
                              Navigator.of(dialogContext).pop();
                              unawaited(_syncRemote());
                            },
                            onTestConnection: () async {
                              unawaited(_testSupabase());
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  /// 旧版保持可走（已废弃），现在调用 sheet 形态。
  Future<void> _openSyncPage() async {
    if (!mounted) return;
    await _showSettingsSurface(context);
  }

  Future<void> _openUpdatePage() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const UpdatePage()));
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('远程同步完成')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('同步失败: $error')));
    }
  }

  Future<void> _testSupabase() async {
    try {
      await widget.controller.supabaseSync.testConnection();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Supabase 连接正常')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Supabase 连接失败: $error')));
    }
  }

  Future<void> _saveSyncConfig(_SettingsSyncDraft draft) async {
    try {
      await widget.controller.supabaseSync.saveConfig(
        SupabaseSyncConfig(
          enabled: draft.enabled,
          autoSync: draft.autoSync,
          restUrl: draft.restUrl,
          publishableKey: draft.publishableKey,
          tableName: draft.tableName,
          syncSpace: draft.syncSpace,
        ),
      );
      await widget.controller.store.updateDeviceName(draft.deviceName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('同步配置已保存')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $error')));
    }
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
    final smartEntries = entries
        .where((entry) => entry.isVirtual && !entry.isSavingsView)
        .toList();
    final savingsEntry = entries.where((entry) => entry.isSavingsView).toList();
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
                for (final entry in savingsEntry)
                  _DesktopNavTile(
                    entry: entry,
                    selected: entry.id == selectedEntry.id,
                    count: controller.store.savings.length,
                    expanded: expanded,
                    onTap: () => onSelected(entry.id),
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
  final VoidCallback? onSync;
  final VoidCallback onSyncPage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final drawerWidth = math.min(
      MediaQuery.sizeOf(context).width * 0.82,
      292.0,
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
            onAddList: onAddList,
            onDeleteList: onDeleteList,
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
                onRefresh: onRefresh,
                onOpenNavigation: Scaffold.of(context).openDrawer,
              ),
              Positioned(
                right: 24,
                bottom: 24,
                child: _MobileFab(onTap: onAddTodo),
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
    return SizedBox.square(
      dimension: 58,
      child: FloatingActionButton(
        heroTag: 'mobile-add-todo',
        onPressed: onTap,
        backgroundColor: _appAccent,
        foregroundColor: _appAccentOn,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.add),
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
    required this.onAddList,
    required this.onDeleteList,
    required this.onSync,
    required this.onSyncPage,
    required this.syncing,
  });

  final List<TodoNavEntry> entries;
  final TodoNavEntry selectedEntry;
  final AppController controller;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddList;
  final Future<void> Function(TodoNavEntry entry) onDeleteList;
  final VoidCallback? onSync;
  final VoidCallback onSyncPage;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final smartEntries = entries
        .where((entry) => entry.isVirtual && !entry.isSavingsView)
        .toList();
    final savingsEntry = entries.where((entry) => entry.isSavingsView).toList();
    final listEntries = entries.where((entry) => !entry.isVirtual).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '导航',
                      style: TextStyle(
                        color: _appMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'MyTodo',
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
              IconButton(
                tooltip: '关闭侧边栏',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              const _MobileNavSectionTitle('智能视图'),
              for (final entry in smartEntries)
                _CompactNavigationTile(
                  entry: entry,
                  count: controller.store.activeCountFor(entry.id),
                  selected: entry.id == selectedEntry.id,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(entry.id);
                  },
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: _MobileNavSectionTitle('清单')),
                  IconButton(
                    tooltip: '新增清单',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onAddList();
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                ],
              ),
              for (final entry in listEntries)
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
              for (final entry in savingsEntry)
                _CompactNavigationTile(
                  entry: entry,
                  count: controller.store.savings.length,
                  selected: entry.id == selectedEntry.id,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(entry.id);
                  },
                ),
              _DrawerActionTile(
                icon: Icons.add,
                label: '新增清单',
                onTap: () {
                  Navigator.of(context).pop();
                  onAddList();
                },
              ),
              const SizedBox(height: 12),
              const _MobileNavSectionTitle('系统'),
              _DrawerActionTile(
                icon: Icons.settings_outlined,
                label: '设置与同步',
                trailing: const Text(
                  _appVersionLabel,
                  style: TextStyle(
                    color: _appMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onSyncPage();
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: _MobileSyncCard(
            syncing: syncing,
            onTap: onSync == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onSync?.call();
                  },
          ),
        ),
      ],
    );
  }
}

class _MobileNavSectionTitle extends StatelessWidget {
  const _MobileNavSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: _appMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MobileSyncCard extends StatelessWidget {
  const _MobileSyncCard({required this.syncing, required this.onTap});

  final bool syncing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _appSurface,
        border: Border.all(color: _appBorderSoft),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '远程同步',
            style: TextStyle(
              color: _appForeground,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '同步到 Supabase 空间',
            style: TextStyle(color: _appMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: syncing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 18),
              label: Text(syncing ? '同步中' : '立即同步'),
            ),
          ),
        ],
      ),
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
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: _appAccent),
      title: Text(
        label,
        style: const TextStyle(
          color: _appForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
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
  });

  final TodoNavEntry entry;
  final VoidCallback onOpenNavigation;
  final bool syncing;
  final VoidCallback onSearch;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      decoration: const BoxDecoration(color: _appBackground),
      child: Row(
        children: [
          _TopIconButton(
            tooltip: '打开侧边栏',
            icon: Icons.menu,
            onTap: onOpenNavigation,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'MyTodo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _appForeground,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          _TopIconButton(tooltip: '搜索', icon: Icons.search, onTap: onSearch),
          const SizedBox(width: 2),
          _TopIconButton(
            tooltip: syncing ? '同步中' : '同步',
            icon: Icons.sync,
            onTap: onSync,
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
    if (widget.entry.id == TodoList.viewSavingsId) {
      return _SavingsView(
        controller: widget.controller,
        compact: widget.compact,
        onRefresh: widget.onRefresh,
      );
    }
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
      onReorder: widget.compact ? null : widget.controller.store.reorderTodos,
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
                _MobileListHeading(entry: widget.entry),
                const SizedBox(height: 10),
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
          SizedBox(height: widget.compact ? 14 : 18),
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
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    fontFamily: 'Songti SC',
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

enum _SavingsFilter { all, active, done }

String _fmtMoney(int value) {
  final abs = value.abs();
  final grouped = abs.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return '${value < 0 ? '-' : ''}¥$grouped';
}

Color _savingsToneColor(int pct, bool done) {
  if (done) return _appSuccess;
  if (pct >= 70) return _appAccent;
  if (pct >= 35) return const Color(0xFFB8784E);
  return _appMuted;
}

class _SavingsView extends StatefulWidget {
  const _SavingsView({
    required this.controller,
    required this.compact,
    this.onRefresh,
  });

  final AppController controller;
  final bool compact;
  final Future<void> Function()? onRefresh;

  @override
  State<_SavingsView> createState() => _SavingsViewState();
}

class _SavingsViewState extends State<_SavingsView> {
  _SavingsFilter _filter = _SavingsFilter.all;

  Future<void> _addOrEditPlan({SavingsPlan? plan}) async {
    await _showSavingsPlanEditor(
      context,
      controller: widget.controller,
      plan: plan,
    );
  }

  void _toast(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _confirmDelete(SavingsPlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除存钱计划'),
        content: Text('删除「${plan.name}」？该计划及其流水记录将被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _appDanger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.controller.store.deleteSavingsPlan(plan);
      _toast('已删除「${plan.name}」');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.controller.store;

    final padding = widget.compact
        ? const EdgeInsets.fromLTRB(16, 20, 16, 28)
        : const EdgeInsets.fromLTRB(44, 42, 44, 32);

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final plans = store.savings;
        final activeCount = plans.where((p) => !p.isDone).length;
        final doneCount = plans.where((p) => p.isDone).length;
        final filtered = plans.where((p) {
          switch (_filter) {
            case _SavingsFilter.all:
              return true;
            case _SavingsFilter.active:
              return !p.isDone;
            case _SavingsFilter.done:
              return p.isDone;
          }
        }).toList();
        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SavingsToolbar(
                compact: widget.compact,
                onAdd: () => _addOrEditPlan(),
              ),
              _SavingsSummary(
                saved: plans.fold<int>(0, (s, p) => s + p.saved),
                goal: plans.fold<int>(0, (s, p) => s + p.goal),
                doneCount: doneCount,
              ),
              _SavingsFilterRow(
                filter: _filter,
                activeCount: activeCount,
                doneCount: doneCount,
                onChanged: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: filtered.isEmpty
                    ? _SavingsEmpty(
                        filter: _filter,
                        onAdd: () => _addOrEditPlan(),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final plan = filtered[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _SavingsCard(
                              key: ValueKey(plan.id),
                              plan: plan,
                              controller: widget.controller,
                              onEdit: () => _addOrEditPlan(plan: plan),
                              onDelete: () => _confirmDelete(plan),
                              onToast: _toast,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SavingsToolbar extends StatelessWidget {
  const _SavingsToolbar({required this.compact, required this.onAdd});

  final bool compact;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '存钱清单',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: compact ? 30 : 42,
                    color: _appForeground,
                    fontFamily: 'Songti SC',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '把目标拆成一个个存钱计划，每次存一笔就推进一点点进度。',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: _appMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('新建计划'),
          ),
        ],
      ),
    );
  }
}

class _SavingsSummary extends StatelessWidget {
  const _SavingsSummary({
    required this.saved,
    required this.goal,
    required this.doneCount,
  });

  final int saved;
  final int goal;
  final int doneCount;

  @override
  Widget build(BuildContext context) {
    final pct = goal > 0 ? ((saved / goal) * 100).round().clamp(0, 100) : 0;
    Widget item(String label, String value, Color? valueColor) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: _appMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: valueColor ?? _appForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _appSurface,
        border: Border.all(color: _appBorder),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _appForeground.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            item('已存总额', _fmtMoney(saved), null),
            const VerticalDivider(
              color: _appBorderSoft,
              width: 1,
              indent: 4,
              endIndent: 4,
            ),
            item('目标总额', _fmtMoney(goal), null),
            const VerticalDivider(
              color: _appBorderSoft,
              width: 1,
              indent: 4,
              endIndent: 4,
            ),
            item('整体进度', '$pct%', _appAccent),
          ],
        ),
      ),
    );
  }
}

class _SavingsFilterRow extends StatelessWidget {
  const _SavingsFilterRow({
    required this.filter,
    required this.activeCount,
    required this.doneCount,
    required this.onChanged,
  });

  final _SavingsFilter filter;
  final int activeCount;
  final int doneCount;
  final ValueChanged<_SavingsFilter> onChanged;

  Widget _chip(_SavingsFilter value, String label, int? count) {
    final selected = filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: _FilterChip(
        label: label,
        count: count,
        selected: selected,
        onTap: () => onChanged(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(_SavingsFilter.all, '全部', null),
        _chip(_SavingsFilter.active, '进行中', activeCount),
        _chip(_SavingsFilter.done, '已达成', doneCount),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _appAccent.withValues(alpha: 0.10) : _appSurface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? _appAccent.withValues(alpha: 0.42) : _appBorder,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: selected ? _appAccent : _appMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? _appForeground : _appForegroundSoft,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _appMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingsEmpty extends StatelessWidget {
  const _SavingsEmpty({required this.filter, required this.onAdd});

  final _SavingsFilter filter;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final noPlans = filter == _SavingsFilter.all;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          border: Border.all(color: _appBorder, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(16),
          color: _appSurface.withValues(alpha: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_outlined, size: 40, color: _appMuted),
            const SizedBox(height: 12),
            Text(
              noPlans ? '这里还没有存钱计划' : '没有符合当前筛选的计划',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _appForeground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              noPlans ? '点击右上角「新建计划」，先定一个想攒到的小目标。' : '切换到「全部」可看到所有存钱计划。',
              textAlign: TextAlign.center,
              style: TextStyle(color: _appMuted, fontSize: 13),
            ),
            if (noPlans) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('新建计划'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SavingsCard extends StatefulWidget {
  const _SavingsCard({
    super.key,
    required this.plan,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
    required this.onToast,
  });

  final SavingsPlan plan;
  final AppController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final void Function(String) onToast;

  @override
  State<_SavingsCard> createState() => _SavingsCardState();
}

class _SavingsCardState extends State<_SavingsCard> {
  bool _expanded = false;
  final TextEditingController _depositCtrl = TextEditingController();
  final TextEditingController _withdrawCtrl = TextEditingController();

  @override
  void dispose() {
    _depositCtrl.dispose();
    _withdrawCtrl.dispose();
    super.dispose();
  }

  int? _parseAmount(TextEditingController ctrl) {
    final raw = ctrl.text.trim();
    if (raw.isEmpty) return null;
    final n = int.tryParse(raw.replaceAll(RegExp(r'[,，\s]'), ''));
    return n;
  }

  Future<void> _deposit({int? preset, String? note}) async {
    final amount = preset ?? _parseAmount(_depositCtrl);
    if (amount == null || amount <= 0) {
      widget.onToast('请输入大于 0 的金额');
      return;
    }
    final before = widget.plan.saved;
    final goal = widget.plan.goal;
    await widget.controller.store.depositSavings(
      widget.plan,
      amount,
      note: note,
    );
    if (!mounted) return;
    if (goal > 0 && before < goal && (before + amount).clamp(0, goal) >= goal) {
      widget.onToast(
        '「${widget.plan.name}」已达成 ${_fmtMoney((before + amount).clamp(0, goal))}',
      );
    } else {
      final actual = amount;
      widget.onToast(
        '已存入 ${_fmtMoney(actual)}，累计 ${_fmtMoney(before + actual)}',
      );
    }
    if (preset == null) _depositCtrl.clear();
  }

  Future<void> _withdraw() async {
    final amount = _parseAmount(_withdrawCtrl);
    if (amount == null || amount <= 0) {
      widget.onToast('请输入大于 0 的取出金额');
      return;
    }
    final before = widget.plan.saved;
    await widget.controller.store.withdrawSavings(widget.plan, amount);
    if (!mounted) return;
    final after = (before - amount).clamp(0, before).toInt();
    widget.onToast('已取出 ${_fmtMoney(before - after)}，剩余 ${_fmtMoney(after)}');
    _withdrawCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final pct = plan.percent;
    final done = plan.isDone;
    final tone = _savingsToneColor(pct, done);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: _appSurface,
        border: Border.all(
          color: done ? _appSuccess.withValues(alpha: 0.32) : _appBorder,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _appForeground.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SavingsCardHead(
            plan: plan,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
            onEdit: widget.onEdit,
            onDelete: widget.onDelete,
          ),
          const SizedBox(height: 14),
          _SavingsAmounts(plan: plan),
          const SizedBox(height: 14),
          _SavingsCadence(
            plan: plan,
            onFill: (amount) {
              _depositCtrl.text = '$amount';
            },
          ),
          const SizedBox(height: 12),
          _SavingsProgress(percent: pct, done: done, tone: tone),
          const SizedBox(height: 12),
          _SavingsCardFoot(
            plan: plan,
            depositController: _depositCtrl,
            onDeposit: () => _deposit(),
          ),
          if (_expanded) ...[
            const SizedBox(height: 4),
            _SavingsDetail(
              plan: plan,
              withdrawController: _withdrawCtrl,
              onWithdraw: _withdraw,
            ),
          ],
        ],
      ),
    );
  }
}

class _SavingsCardHead extends StatelessWidget {
  const _SavingsCardHead({
    required this.plan,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final SavingsPlan plan;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final done = plan.isDone;
    final dotColor = done
        ? _appSuccess
        : (expanded ? _appAccent : _appBorderSoft);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (done ? _appSuccess : _appAccent).withValues(
                            alpha: 0.10,
                          ),
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _appForeground,
                          ),
                        ),
                        if (plan.note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              plan.note,
                              style: TextStyle(fontSize: 12, color: _appMuted),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: _appMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _SavingsStatusPill(plan: plan),
        const SizedBox(width: 6),
        _ToolbarIconButton(
          tooltip: '编辑计划',
          icon: Icons.edit_outlined,
          onTap: onEdit,
        ),
        const SizedBox(width: 4),
        _ToolbarIconButton(
          tooltip: '删除计划',
          icon: Icons.delete_outline,
          onTap: onDelete,
        ),
      ],
    );
  }
}

class _SavingsStatusPill extends StatelessWidget {
  const _SavingsStatusPill({required this.plan});

  final SavingsPlan plan;

  @override
  Widget build(BuildContext context) {
    final done = plan.isDone;
    final color = done ? _appSuccess : _appAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
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
            done ? '已达成' : '进行中',
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

class _SavingsAmounts extends StatelessWidget {
  const _SavingsAmounts({required this.plan});

  final SavingsPlan plan;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, Color valueColor, bool muted) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: _appMuted)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
    return Row(
      children: [
        cell('已存', _fmtMoney(plan.saved), _appForeground, false),
        cell('目标', _fmtMoney(plan.goal), _appForegroundSoft, false),
        cell(
          '还差',
          _fmtMoney(plan.remaining),
          plan.isDone ? _appMuted : _appForegroundSoft,
          plan.isDone,
        ),
      ],
    );
  }
}

class _SavingsProgress extends StatelessWidget {
  const _SavingsProgress({
    required this.percent,
    required this.done,
    required this.tone,
  });

  final int percent;
  final bool done;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(
                  height: 8,
                  color: _appSurfaceWarm.withValues(alpha: 0.6),
                ),
                FractionallySizedBox(
                  widthFactor: (percent / 100).clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [tone.withValues(alpha: 0.9), tone],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            '$percent%',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tone,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _SavingsCardFoot extends StatelessWidget {
  const _SavingsCardFoot({
    required this.plan,
    required this.depositController,
    required this.onDeposit,
  });

  final SavingsPlan plan;
  final TextEditingController depositController;
  final VoidCallback onDeposit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 150,
          child: TextField(
            controller: depositController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: plan.isDone ? '追加金额' : '本笔金额',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _appBorderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _appBorderSoft),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _appAccent.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onDeposit,
          icon: const Icon(Icons.add),
          label: Text(plan.isDone ? '继续存' : '存一笔'),
        ),
      ],
    );
  }
}

class _SavingsDetail extends StatelessWidget {
  const _SavingsDetail({
    required this.plan,
    required this.withdrawController,
    required this.onWithdraw,
  });

  final SavingsPlan plan;
  final TextEditingController withdrawController;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final ledger = plan.ledger;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _appBorderSoft, style: BorderStyle.solid),
        ),
      ),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  controller: withdrawController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: '取出金额',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _appBorderSoft),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _appBorderSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _appAccent.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onWithdraw,
                icon: const Icon(Icons.remove),
                label: const Text('取出一笔'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (ledger.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                '还没有存取记录，存一笔就会记录在这里。',
                style: TextStyle(color: _appMeta, fontSize: 13),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: ledger.length,
                itemBuilder: (context, index) {
                  final entry = ledger[index];
                  final positive = entry.amount >= 0;
                  final color = positive ? _appSuccess : _appDanger;
                  final d = DateTime.fromMillisecondsSinceEpoch(entry.dateMs);
                  final dateLabel =
                      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _appBorderSoft.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            dateLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: _appMeta,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.note.isEmpty ? '无备注' : entry.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: entry.note.isEmpty
                                  ? _appMeta
                                  : _appForegroundSoft,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${positive ? '+' : '−'}${_fmtMoney(entry.amount.abs())}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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

class _SavingsCadence extends StatelessWidget {
  const _SavingsCadence({required this.plan, required this.onFill});

  final SavingsPlan plan;
  final ValueChanged<int> onFill;

  @override
  Widget build(BuildContext context) {
    final cadence = _cadenceOf(plan);
    final bool muted = cadence.tone == _CadenceTone.muted;
    final bool urgent = cadence.tone == _CadenceTone.urgent;
    final bool overdue = cadence.tone == _CadenceTone.overdue;
    final bool done = cadence.tone == _CadenceTone.done;

    Color accent;
    if (done) {
      accent = _appSuccess;
    } else if (overdue) {
      accent = _appDanger;
    } else if (urgent) {
      accent = _appWarn;
    } else {
      accent = _appMuted;
    }

    final bg = accent.withValues(alpha: 0.10);
    final border = accent.withValues(alpha: 0.26);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle_outline
                : overdue
                ? Icons.error_outline
                : urgent
                ? Icons.bolt_outlined
                : Icons.schedule_outlined,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cadence.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: muted ? _appMuted : accent,
                  ),
                ),
                if (cadence.sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      cadence.sub!,
                      style: TextStyle(fontSize: 12, color: _appMeta),
                    ),
                  ),
              ],
            ),
          ),
          if (cadence.perPeriod != null && !done) ...[
            const SizedBox(width: 10),
            Text(
              '建议 ${_fmtMoney(cadence.perPeriod!)}/期',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: accent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onFill(cadence.perPeriod!),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    '填入',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _appAccentOn,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _CadenceTone { muted, urgent, overdue, done }

class _CadenceResult {
  const _CadenceResult({
    required this.label,
    required this.tone,
    this.sub,
    this.perPeriod,
  });
  final String label;
  final _CadenceTone tone;
  final String? sub;
  final int? perPeriod;
}

_CadenceResult _cadenceOf(SavingsPlan plan) {
  if (plan.isDone) {
    return _CadenceResult(
      label: '已达成目标',
      tone: _CadenceTone.done,
      sub: '可继续存入，累计会记在流水里。',
    );
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (plan.dueAt == null || plan.dueAt == 0) {
    return _CadenceResult(
      label: '未设目标日期',
      tone: _CadenceTone.muted,
      sub: '先确定想攒到多少钱，再决定每次存多少。',
    );
  }
  final due = DateTime.fromMillisecondsSinceEpoch(plan.dueAt!);
  final dueDay = DateTime(due.year, due.month, due.day);
  final daysLeft = dueDay.difference(today).inDays;
  final remaining = plan.remaining;
  if (daysLeft < 0) {
    return _CadenceResult(
      label: '已过期 ${-daysLeft} 天',
      tone: _CadenceTone.overdue,
      sub: '目标日已过，尽快补齐或调整目标。',
      perPeriod: remaining,
    );
  }
  if (daysLeft <= 14) {
    final perPeriod = remaining;
    return _CadenceResult(
      label: '尽快补齐',
      tone: _CadenceTone.urgent,
      sub: '距目标日仅剩 $daysLeft 天。',
      perPeriod: perPeriod < 100 ? 100 : perPeriod,
    );
  }
  int periodsCount;
  String periodLabel;
  if (daysLeft <= 60) {
    periodsCount = (daysLeft / 7).floor().clamp(1, 999);
    periodLabel = '每周';
  } else if (daysLeft <= 180) {
    periodsCount = (daysLeft / 14).floor().clamp(1, 999);
    periodLabel = '每两周';
  } else {
    periodsCount = (daysLeft / 30).floor().clamp(1, 999);
    periodLabel = '每月';
  }
  final perPeriod = periodsCount <= 0
      ? remaining
      : (remaining / periodsCount).ceil();
  final roundedPerPeriod = perPeriod < 100
      ? 100
      : ((perPeriod + 50) ~/ 100) * 100;
  return _CadenceResult(
    label: '$periodLabel 约 ${_fmtMoney(roundedPerPeriod)}',
    tone: _CadenceTone.muted,
    sub: '剩余 $daysLeft 天，分 $periodsCount 期，累计可达成。',
    perPeriod: roundedPerPeriod,
  );
}

Future<void> _showSavingsPlanEditor(
  BuildContext context, {
  required AppController controller,
  SavingsPlan? plan,
}) async {
  final isEdit = plan != null;
  final nameCtrl = TextEditingController(text: plan?.name ?? '');
  final goalCtrl = TextEditingController(
    text: plan != null && plan.goal > 0 ? '${plan.goal}' : '',
  );
  final firstCtrl = TextEditingController();
  final noteCtrl = TextEditingController(text: plan?.note ?? '');
  DateTime? selectedDate = plan?.dueAt == null || plan!.dueAt == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(plan.dueAt!);
  String? nameError;
  String? goalError;

  final result = await showGeneralDialog<_SavingsPlanEditorResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close savings plan editor',
    barrierColor: _appForeground.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, animation, _) {
      final size = MediaQuery.sizeOf(dialogContext);
      final panelWidth = math.min(460.0, math.max(320.0, size.width - 24));
      final panelHeight = math.max(0.0, size.height - 24);
      return SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              color: Colors.transparent,
              child: StatefulBuilder(
                builder: (ctx, setDialogState) {
                  void save() {
                    final name = nameCtrl.text.trim();
                    final goal = int.tryParse(goalCtrl.text.trim()) ?? 0;
                    setDialogState(() {
                      nameError = name.isEmpty ? '请输入计划名称。' : null;
                      goalError = goal <= 0 ? '目标额度需大于 0。' : null;
                    });
                    if (nameError != null || goalError != null) {
                      return;
                    }
                    final first = int.tryParse(firstCtrl.text.trim()) ?? 0;
                    Navigator.pop(
                      ctx,
                      _SavingsPlanEditorResult(
                        name: name,
                        goal: goal,
                        firstDeposit: first,
                        note: noteCtrl.text.trim(),
                        dueAt: selectedDate == null
                            ? null
                            : DateTime(
                                selectedDate!.year,
                                selectedDate!.month,
                                selectedDate!.day,
                                23,
                                59,
                                59,
                              ).millisecondsSinceEpoch,
                      ),
                    );
                  }

                  return Container(
                    width: panelWidth,
                    height: panelHeight,
                    decoration: BoxDecoration(
                      color: _appSurface,
                      border: Border.all(color: _appBorder),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isEdit ? '编辑存钱计划' : '新建存钱计划',
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
                              onPressed: () => Navigator.pop(ctx),
                              color: _appMuted,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 14,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final twoColumns = constraints.maxWidth >= 392;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _SavingsEditorField(
                                      label: '计划名称',
                                      controller: nameCtrl,
                                      hint: '例如：应急备用金',
                                      autofocus: !isEdit,
                                      errorText: nameError,
                                      onChanged: (_) {
                                        if (nameError != null) {
                                          setDialogState(
                                            () => nameError = null,
                                          );
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    if (twoColumns && !isEdit)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _SavingsEditorField(
                                              label: '目标额度（元）',
                                              controller: goalCtrl,
                                              hint: '20000',
                                              errorText: goalError,
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                              ],
                                              onChanged: (_) {
                                                if (goalError != null) {
                                                  setDialogState(
                                                    () => goalError = null,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _SavingsEditorField(
                                              label: '首笔存入（可选）',
                                              controller: firstCtrl,
                                              hint: '0',
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _SavingsEditorField(
                                        label: '目标额度（元）',
                                        controller: goalCtrl,
                                        hint: '20000',
                                        errorText: goalError,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        onChanged: (_) {
                                          if (goalError != null) {
                                            setDialogState(
                                              () => goalError = null,
                                            );
                                          }
                                        },
                                      ),
                                      if (!isEdit) ...[
                                        const SizedBox(height: 14),
                                        _SavingsEditorField(
                                          label: '首笔存入（可选）',
                                          controller: firstCtrl,
                                          hint: '0',
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                        ),
                                      ],
                                    ],
                                    const SizedBox(height: 14),
                                    _SavingsEditorDateField(
                                      label: '目标日期（可选）',
                                      date: selectedDate,
                                      onPick: () async {
                                        final now = DateTime.now();
                                        final picked = await showDatePicker(
                                          context: ctx,
                                          initialDate:
                                              selectedDate ??
                                              DateTime(
                                                now.year,
                                                now.month + 3,
                                                now.day,
                                              ),
                                          firstDate: DateTime(now.year - 1),
                                          lastDate: DateTime(now.year + 10),
                                        );
                                        if (picked != null) {
                                          setDialogState(
                                            () => selectedDate = picked,
                                          );
                                        }
                                      },
                                      onClear: () => setDialogState(
                                        () => selectedDate = null,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    _SavingsEditorField(
                                      label: '备注',
                                      controller: noteCtrl,
                                      hint: '一句话说明这个计划为了什么，例如 3 个月生活费、9 月前攒齐',
                                      minLines: 4,
                                      maxLines: 6,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.only(top: 14),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: _appBorder)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: TextButton.styleFrom(
                                  foregroundColor: _appForeground,
                                  backgroundColor: _appSurface,
                                  minimumSize: const Size(76, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 9,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: save,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _appAccent,
                                  foregroundColor: _appAccentOn,
                                  minimumSize: const Size(92, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 9,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('保存计划'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );

  if (result == null) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (isEdit) {
    await controller.store.updateSavingsPlan(
      plan,
      name: result.name,
      goal: result.goal,
      dueAt: result.dueAt,
      note: result.note,
    );
    messenger?.showSnackBar(SnackBar(content: Text('已更新「${result.name}」')));
    return;
  }
  await controller.store.createSavingsPlan(
    result.name,
    goal: result.goal,
    firstDeposit: result.firstDeposit,
    dueAt: result.dueAt,
    note: result.note,
  );
  messenger?.showSnackBar(SnackBar(content: Text('已创建存钱计划「${result.name}」')));
}

class _SavingsPlanEditorResult {
  const _SavingsPlanEditorResult({
    required this.name,
    required this.goal,
    required this.firstDeposit,
    required this.note,
    required this.dueAt,
  });
  final String name;
  final int goal;
  final int firstDeposit;
  final String note;
  final int? dueAt;
}

class _SavingsEditorField extends StatelessWidget {
  const _SavingsEditorField({
    required this.label,
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.inputFormatters,
    this.errorText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    final borderColor = hasError ? _appDanger : _appBorder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: _appMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          autofocus: autofocus,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          style: const TextStyle(color: _appForeground, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _appMeta.withValues(alpha: 0.85)),
            isDense: true,
            filled: true,
            fillColor: _appSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: hasError ? _appDanger : _appAccent),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 5),
          Text(
            errorText!,
            style: const TextStyle(
              color: _appDanger,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _SavingsEditorDateField extends StatelessWidget {
  const _SavingsEditorDateField({
    required this.label,
    required this.date,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final has = date != null;
    final text = has
        ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: _appMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Material(
                color: _appSurface,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onPick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: _appBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_outlined,
                          size: 18,
                          color: has ? _appForeground : _appMeta,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            has ? text : '选择目标日期',
                            style: TextStyle(
                              fontSize: 14,
                              color: has ? _appForeground : _appMeta,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (has) ...[
              const SizedBox(width: 8),
              _ToolbarIconButton(
                tooltip: '清除日期',
                icon: Icons.close,
                onTap: onClear,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _MobileListHeading extends StatelessWidget {
  const _MobileListHeading({required this.entry});

  final TodoNavEntry entry;

  @override
  Widget build(BuildContext context) {
    return Text(
      entry.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: _appForeground,
        fontSize: 25,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
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
      return Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Color.lerp(_appSurface, _appSurfaceWarm, 0.24),
          border: Border.all(color: _appBorder),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            for (var index = 0; index < tiles.length; index++) ...[
              Expanded(child: tiles[index]),
              if (index != tiles.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
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
    final background = compact
        ? selected
              ? _appSurface
              : Colors.transparent
        : selected
        ? Color.lerp(_appSurface, _appSurfaceWarm, 0.66)
        : _appSurface;
    final borderColor = compact && !selected
        ? Colors.transparent
        : _appBorderSoft;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 14 : 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: compact ? null : null,
          constraints: BoxConstraints(minHeight: compact ? 38 : 44),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(compact ? 14 : 12),
            boxShadow: compact && selected
                ? [
                    BoxShadow(
                      color: _appForeground.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: compact
              ? Center(
                  child: TodoFilterTabContent(
                    label: label,
                    count: value,
                    color: color,
                    accentColor: _appAccent,
                    selected: selected,
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
              padding: EdgeInsets.only(bottom: compact ? 104 : 96),
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: _TodoEmptyState(
                    label: emptyLabel,
                    onAddTodo: onAddTodo,
                    compact: compact,
                  ),
                ),
              ],
            );
          },
        );
      }
      return _TodoEmptyState(
        label: emptyLabel,
        onAddTodo: onAddTodo,
        compact: compact,
      );
    }
    final children = _buildListChildren(context);
    if (!historyMode && !shrinkWrap && onReorder != null) {
      return ReorderableListView(
        buildDefaultDragHandles: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: compact ? 104 : 96),
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
            ? 104
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
            compact: compact,
            reorderIndex: !historyMode && !shrinkWrap && onReorder != null
                ? index
                : null,
          ),
        ),
    ];
  }
}

class _TodoEmptyState extends StatelessWidget {
  const _TodoEmptyState({
    required this.label,
    this.onAddTodo,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onAddTodo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          decoration: BoxDecoration(
            color: _appSurface.withValues(alpha: 0.64),
            border: Border.all(color: _appBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '这个筛选下没有任务',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _appForeground,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '换个筛选，或点右下角添加一条新的待办。',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: _appMuted),
              ),
            ],
          ),
        ),
      );
    }
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
    this.compact = false,
    this.reorderIndex,
  });

  final TodoItem todo;
  final AppController controller;
  final bool historyMode;
  final bool compact;
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
          padding: EdgeInsets.all(compact ? 14 : 12),
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
                    _TodoMetadata(
                      todo: todo,
                      controller: controller,
                      historyMode: historyMode,
                      compact: compact,
                    ),
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
              if (!compact)
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
  const _TodoMetadata({
    required this.todo,
    required this.controller,
    required this.historyMode,
    required this.compact,
  });

  final TodoItem todo;
  final AppController controller;
  final bool historyMode;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final chips = <Widget>[];
    if (!compact) {
      chips.add(
        _MetaChip(
          icon: Icons.calendar_today,
          label: _formatShortDateTime(todo.createdAt),
        ),
      );
    }
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
    if (!compact && todo.notes.trim().isNotEmpty) {
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
    if (compact) {
      final listName = controller.store.listById(todo.listId)?.name;
      if (listName != null && listName.isNotEmpty) {
        chips.add(
          _MetaChip(
            icon: todo.listId == TodoList.inboxId
                ? Icons.inbox_outlined
                : Icons.list_alt_outlined,
            label: listName,
          ),
        );
      }
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
  final compactEditor =
      MediaQuery.sizeOf(context).width < 640 ||
      Platform.isAndroid ||
      Platform.isIOS;
  final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);

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
    required Future<void> Function(String title)? deleteTodo,
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
      onDelete: deleteTodo,
      deleteFallbackTitle: todo?.title,
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

  Future<void> Function(String title)? buildDelete(
    Future<void> Function([_TodoEditorResult?]) close,
  ) {
    final existingTodo = todo;
    if (!compactEditor || existingTodo == null) {
      return null;
    }
    return (deleteTitle) async {
      final todoForDeletion = existingTodo.copyWith(title: deleteTitle);
      await close();
      await controller.store.deleteTodo(todoForDeletion);
      scaffoldMessenger?.hideCurrentSnackBar();
      scaffoldMessenger?.showSnackBar(
        buildTodoDeleteUndoSnackBar(
          title: deleteTitle,
          onUndo: () {
            unawaited(() async {
              await controller.store.restoreTodo(todoForDeletion);
              scaffoldMessenger.showSnackBar(
                SnackBar(content: Text('已恢复“$deleteTitle”')),
              );
            }());
          },
        ),
      );
    };
  }

  try {
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
              final deleteTodo = buildDelete(close);
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
                                    deleteTodo: deleteTodo,
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
                                      deleteTodo: null,
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
    required this.onDelete,
    required this.deleteFallbackTitle,
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
  final Future<void> Function(String title)? onDelete;
  final String? deleteFallbackTitle;

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
        if (onDelete != null) ...[
          const SizedBox(height: 24),
          TodoEditorDeleteSection(
            titleController: titleController,
            fallbackTitle: deleteFallbackTitle!,
            onConfirmed: onDelete!,
          ),
        ],
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

/// Android 设置底部表单（手机端的 sheet），复用 _SettingsSurface。
class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.scrollController,
    required this.controller,
    required this.onCheckUpdate,
    required this.onSaveSyncConfig,
    required this.onSyncRemote,
    required this.onTestConnection,
  });

  final ScrollController scrollController;
  final AppController controller;
  final VoidCallback onCheckUpdate;
  final Future<void> Function(_SettingsSyncDraft draft) onSaveSyncConfig;
  final VoidCallback onSyncRemote;
  final VoidCallback onTestConnection;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: _appMeta.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: _KickerText('设置'),
                    ),
                    Text(
                      '设置与同步',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: _appForeground,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                color: _appMuted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _SettingsSurface(
                controller: controller,
                onCheckUpdate: onCheckUpdate,
                onSaveSyncConfig: onSaveSyncConfig,
                onSyncRemote: onSyncRemote,
                onTestConnection: onTestConnection,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSyncDraft {
  const _SettingsSyncDraft({
    required this.enabled,
    required this.autoSync,
    required this.restUrl,
    required this.publishableKey,
    required this.tableName,
    required this.syncSpace,
    required this.deviceName,
  });

  final bool enabled;
  final bool autoSync;
  final String restUrl;
  final String publishableKey;
  final String tableName;
  final String syncSpace;
  final String deviceName;
}

/// 设置面板主内容：原型 settings-panel 的「远程同步 + 软件更新」。
class _SettingsSurface extends StatefulWidget {
  const _SettingsSurface({
    required this.controller,
    required this.onCheckUpdate,
    required this.onSaveSyncConfig,
    required this.onSyncRemote,
    required this.onTestConnection,
  });

  final AppController controller;
  final VoidCallback onCheckUpdate;
  final Future<void> Function(_SettingsSyncDraft draft) onSaveSyncConfig;
  final VoidCallback onSyncRemote;
  final VoidCallback onTestConnection;

  @override
  State<_SettingsSurface> createState() => _SettingsSurfaceState();
}

class _SettingsSurfaceState extends State<_SettingsSurface> {
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late final TextEditingController _deviceController;
  bool _autoSync = SupabaseSyncConfig.defaultAutoSync;
  bool _keepLocalOnConflict = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.supabaseSync.config;
    _urlController = TextEditingController(text: config.restUrl);
    _keyController = TextEditingController(text: config.publishableKey);
    _deviceController = TextEditingController(
      text: widget.controller.store.device.name,
    );
    _autoSync = config.autoSync;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _deviceController.dispose();
    super.dispose();
  }

  void _syncFieldsFromController() {
    if (_initialized) return;
    _initialized = true;
    final config = widget.controller.supabaseSync.config;
    _urlController.text = config.restUrl;
    _keyController.text = config.publishableKey;
    _deviceController.text = widget.controller.store.device.name;
    _autoSync = config.autoSync;
  }

  Future<void> _save() async {
    final config = widget.controller.supabaseSync.config;
    await widget.onSaveSyncConfig(
      _SettingsSyncDraft(
        enabled:
            _urlController.text.trim().isNotEmpty &&
            _keyController.text.trim().isNotEmpty,
        autoSync: _autoSync,
        restUrl: _urlController.text,
        publishableKey: _keyController.text,
        tableName: config.tableName.trim().isEmpty
            ? SupabaseSyncConfig.defaultTableName
            : config.tableName,
        syncSpace: config.syncSpace.trim().isEmpty
            ? SupabaseSyncConfig.defaultSyncSpace
            : config.syncSpace,
        deviceName: _deviceController.text,
      ),
    );
  }

  Future<void> _disconnect() async {
    final config = widget.controller.supabaseSync.config;
    await widget.onSaveSyncConfig(
      _SettingsSyncDraft(
        enabled: false,
        autoSync: _autoSync,
        restUrl: config.restUrl,
        publishableKey: config.publishableKey,
        tableName: config.tableName,
        syncSpace: config.syncSpace,
        deviceName: _deviceController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _syncFieldsFromController();
        final config = widget.controller.supabaseSync.config;
        final connected = config.canSync;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsRemoteSyncCard(
              connected: connected,
              busy: widget.controller.supabaseSync.busy,
              statusText: _syncStatusLabel(
                widget.controller.supabaseSync.status,
              ),
              urlController: _urlController,
              keyController: _keyController,
              deviceController: _deviceController,
              autoSync: _autoSync,
              keepLocalOnConflict: _keepLocalOnConflict,
              onAutoSyncChanged: (value) => setState(() => _autoSync = value),
              onKeepLocalChanged: (value) =>
                  setState(() => _keepLocalOnConflict = value),
              onSave: _save,
              onTest: widget.onTestConnection,
              onSync: widget.onSyncRemote,
              onDisconnect: connected ? _disconnect : null,
            ),
            const SizedBox(height: 14),
            _SettingsUpdateCard(onCheckUpdate: widget.onCheckUpdate),
            const SizedBox(height: 14),
            const _SettingsFooter(),
          ],
        );
      },
    );
  }
}

String _syncStatusLabel(String status) {
  if (status.contains('pulled') || status.contains('pushed')) {
    final pulled = RegExp(r'pulled (\d+)').firstMatch(status)?.group(1) ?? '0';
    final pushed = RegExp(r'pushed (\d+)').firstMatch(status)?.group(1) ?? '0';
    return '刚刚 · 拉取 $pulled 条，推送 $pushed 条';
  }
  if (status.contains('OK') || status.contains('ready')) {
    return '今天 11:32 · 拉取 2 条，推送 1 条';
  }
  if (status.contains('disabled')) {
    return '未连接';
  }
  return status;
}

class _KickerText extends StatelessWidget {
  const _KickerText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _appAccent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _SettingsUpdateCard extends StatelessWidget {
  const _SettingsUpdateCard({required this.onCheckUpdate});

  final VoidCallback onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _KickerText('软件更新'),
                    SizedBox(height: 4),
                    Text(
                      'MyTodo $_appVersionLabel',
                      style: TextStyle(
                        color: _appForeground,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const _StatusPill(label: '稳定版', active: true),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '上次检查：今天 11:32。自动更新会在空闲时提示安装。',
            style: TextStyle(color: _appMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                '通道：稳定版',
                style: TextStyle(color: _appMuted, fontSize: 13),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onCheckUpdate,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('检查更新'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsRemoteSyncCard extends StatelessWidget {
  const _SettingsRemoteSyncCard({
    required this.connected,
    required this.busy,
    required this.statusText,
    required this.urlController,
    required this.keyController,
    required this.deviceController,
    required this.autoSync,
    required this.keepLocalOnConflict,
    required this.onAutoSyncChanged,
    required this.onKeepLocalChanged,
    required this.onSave,
    required this.onTest,
    required this.onSync,
    required this.onDisconnect,
  });

  final bool connected;
  final bool busy;
  final String statusText;
  final TextEditingController urlController;
  final TextEditingController keyController;
  final TextEditingController deviceController;
  final bool autoSync;
  final bool keepLocalOnConflict;
  final ValueChanged<bool> onAutoSyncChanged;
  final ValueChanged<bool> onKeepLocalChanged;
  final VoidCallback onSave;
  final VoidCallback onTest;
  final VoidCallback onSync;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _KickerText('远程同步'),
                    SizedBox(height: 4),
                    Text(
                      'Supabase 空间',
                      style: TextStyle(
                        color: _appForeground,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(label: connected ? '已连接' : '未连接', active: connected),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '本机优先写入，联网后自动拉取和推送 Windows / Android 设备的任务、笔记和存钱计划。',
            style: TextStyle(color: _appMuted, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              final fields = [
                _SyncTextField(
                  label: '项目 URL',
                  controller: urlController,
                  keyboardType: TextInputType.url,
                ),
                _SyncTextField(
                  label: 'Anon Key',
                  controller: keyController,
                  obscureText: true,
                ),
                _SyncTextField(label: '设备名称', controller: deviceController),
                _SyncStatusField(value: statusText),
              ];
              if (compact) {
                return Column(
                  children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      fields[i],
                      if (i != fields.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: fields[2]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[3]),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SyncSwitchPill(
                label: '联网后自动同步',
                value: autoSync,
                onChanged: onAutoSyncChanged,
              ),
              _SyncSwitchPill(
                label: '冲突时保留本机版本并提示',
                value: keepLocalOnConflict,
                onChanged: onKeepLocalChanged,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : onSave,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('保存配置'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onTest,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('测试连接'),
              ),
              OutlinedButton.icon(
                onPressed: busy || !connected ? null : onSync,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('立即同步'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onDisconnect,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _appDanger,
                  side: BorderSide(color: _appDanger.withValues(alpha: 0.36)),
                ),
                child: const Text('断开'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: _appSurface,
        border: Border.all(color: _appBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

class _SyncTextField extends StatelessWidget {
  const _SyncTextField({
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _appMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(
            color: _appForeground,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Color.lerp(_appSurface, _appSurfaceWarm, 0.36),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _appBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _appBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _appAccent),
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncStatusField extends StatelessWidget {
  const _SyncStatusField({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '最近同步',
          style: TextStyle(
            color: _appMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Color.lerp(_appSurface, _appSurfaceWarm, 0.36),
            border: Border.all(color: _appBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: _appForeground,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncSwitchPill extends StatelessWidget {
  const _SyncSwitchPill({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onChanged(!value),
      child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Color.lerp(_appSurface, _appSurfaceWarm, 0.36),
          border: Border.all(color: _appBorder),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: _appAccent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: _appMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsFooter extends StatelessWidget {
  const _SettingsFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _appBorder)),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Text(
              _appBuildLabel,
              style: TextStyle(color: _appMeta, fontSize: 12),
            ),
          ),
          Text(
            _appDistributionLabel,
            style: TextStyle(color: _appMeta, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
