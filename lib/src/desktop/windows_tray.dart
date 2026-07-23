import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueChanged, kIsWeb;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app_controller.dart';

const _windowIconPath = 'assets/brand/mytodo_taskbar.ico';
const _trayIconPath = 'assets/brand/mytodo_tray.ico';

Future<void> initializeWindowsWindow() async {
  if (kIsWeb || !Platform.isWindows) {
    return;
  }

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1180, 760),
    minimumSize: Size(900, 560),
    center: true,
    skipTaskbar: false,
    title: 'MyTodo',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () {
    unawaited(windowManager.show());
    unawaited(windowManager.focus());
  });
}

class WindowsTrayController with TrayListener, WindowListener {
  WindowsTrayController(this.controller, {required this.onWidgetModeChanged});

  final AppController controller;
  final ValueChanged<bool> onWidgetModeChanged;
  bool _initialized = false;
  bool _quitting = false;
  bool _refreshQueued = false;
  bool _widgetMode = false;
  bool _fullWindowWasMaximized = false;
  Size? _fullWindowSize;
  Offset? _fullWindowPosition;

  bool get widgetMode => _widgetMode;

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isWindows || _initialized) {
      return;
    }
    _initialized = true;

    trayManager.addListener(this);
    windowManager.addListener(this);
    controller.addListener(_queueTrayRefresh);

    await windowManager.setPreventClose(true);
    await windowManager.setIcon(_windowIconPath);
    await trayManager.setIcon(_trayIconPath);
    await _refreshTrayPresentation();
  }

  void dispose() {
    if (!_initialized) {
      return;
    }
    controller.removeListener(_queueTrayRefresh);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }

  void _queueTrayRefresh() {
    if (_refreshQueued || _quitting) {
      return;
    }
    _refreshQueued = true;
    scheduleMicrotask(() async {
      _refreshQueued = false;
      if (!_quitting) {
        await _refreshTrayPresentation();
      }
    });
  }

  Future<void> _refreshTrayPresentation() async {
    final todos = controller.store.todos;
    final active = todos.where((todo) => !todo.completed).length;
    final completed = todos.where((todo) => todo.completed).length;

    await trayManager.setToolTip('MyTodo - 当前 $active，完成 $completed');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: 'status',
            label: '当前 $active · 完成 $completed',
            disabled: true,
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'show',
            label: _widgetMode ? '打开完整 MyTodo' : '打开 MyTodo',
          ),
          MenuItem(key: 'widget', label: _widgetMode ? '退出小组件模式' : '显示桌面小组件'),
          MenuItem(key: 'sync', label: '立即远程同步'),
          MenuItem(key: 'hide', label: '隐藏到托盘'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: '退出'),
        ],
      ),
    );
  }

  Future<void> showWindow() async {
    if (kIsWeb || !Platform.isWindows || _quitting) {
      return;
    }
    await windowManager.setSkipTaskbar(_widgetMode);
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
    await _refreshTrayPresentation();
  }

  Future<void> enterWidgetMode() async {
    if (kIsWeb || !Platform.isWindows || _quitting || _widgetMode) {
      return;
    }
    _fullWindowSize = await windowManager.getSize();
    _fullWindowPosition = await windowManager.getPosition();
    _fullWindowWasMaximized = await windowManager.isMaximized();
    if (_fullWindowWasMaximized) {
      await windowManager.unmaximize();
    }
    _widgetMode = true;
    onWidgetModeChanged(true);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(320, 400));
    await windowManager.setSize(const Size(360, 520), animate: true);
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.show();
    await windowManager.focus();
    await _refreshTrayPresentation();
  }

  Future<void> exitWidgetMode() async {
    if (kIsWeb || !Platform.isWindows || _quitting || !_widgetMode) {
      return;
    }
    _widgetMode = false;
    onWidgetModeChanged(false);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(900, 560));
    await windowManager.setSize(
      _fullWindowSize ?? const Size(1180, 760),
      animate: true,
    );
    final position = _fullWindowPosition;
    if (!_fullWindowWasMaximized && position != null) {
      await windowManager.setPosition(position, animate: true);
    }
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    if (_fullWindowWasMaximized) {
      await windowManager.maximize();
    }
    await windowManager.focus();
    await _refreshTrayPresentation();
  }

  Future<void> toggleWidgetMode() async {
    if (_widgetMode) {
      await exitWidgetMode();
    } else {
      await enterWidgetMode();
    }
  }

  Future<void> hideToTray() async {
    if (kIsWeb || !Platform.isWindows || _quitting) {
      return;
    }
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
    await _refreshTrayPresentation();
  }

  Future<void> quit() async {
    if (kIsWeb || !Platform.isWindows || _quitting) {
      return;
    }
    _quitting = true;
    controller.removeListener(_queueTrayRefresh);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onWindowClose() {
    if (_quitting) {
      return;
    }
    unawaited(hideToTray());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_widgetMode ? exitWidgetMode() : showWindow());
        break;
      case 'widget':
        unawaited(toggleWidgetMode());
        break;
      case 'sync':
        unawaited(_syncFromTray());
        break;
      case 'hide':
        unawaited(hideToTray());
        break;
      case 'quit':
        unawaited(quit());
        break;
    }
  }

  Future<void> _syncFromTray() async {
    if (controller.supabaseSync.config.canSync) {
      await controller.supabaseSync.syncNow();
    }
    await _refreshTrayPresentation();
  }
}
