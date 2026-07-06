import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app_controller.dart';

const _trayIconPath = 'assets/brand/mytodo_tray.ico';

Future<void> initializeWindowsWindow() async {
  if (kIsWeb || !Platform.isWindows) {
    return;
  }

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1080, 760),
    minimumSize: Size(760, 560),
    center: true,
    skipTaskbar: false,
    title: 'MyTodo',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () {
    unawaited(windowManager.show());
    unawaited(windowManager.focus());
  });
}

class WindowsTrayController with TrayListener, WindowListener {
  WindowsTrayController(this.controller);

  final AppController controller;
  bool _initialized = false;
  bool _quitting = false;
  bool _refreshQueued = false;

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isWindows || _initialized) {
      return;
    }
    _initialized = true;

    trayManager.addListener(this);
    windowManager.addListener(this);
    controller.addListener(_queueTrayRefresh);

    await windowManager.setPreventClose(true);
    await windowManager.setIcon(_trayIconPath);
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
          MenuItem(key: 'show', label: '打开 MyTodo'),
          MenuItem(key: 'sync', label: '立即同步'),
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
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
    await _refreshTrayPresentation();
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
        unawaited(showWindow());
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
    await controller.sync.syncAllTrustedDevices();
    await _refreshTrayPresentation();
  }
}
