import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/todo_store.dart';
import 'sync/supabase_sync_service.dart';
import 'widget/todo_widget_service.dart';

class AppController extends ChangeNotifier {
  AppController._({
    required this.store,
    required this.supabaseSync,
    required this.todoWidget,
  }) {
    store.addListener(_onStoreChanged);
    supabaseSync.addListener(notifyListeners);
  }

  final TodoStore store;
  final SupabaseSyncService supabaseSync;
  final TodoWidgetService todoWidget;
  Timer? _dailyRefreshTimer;
  bool _disposed = false;

  static Future<AppController> create() async {
    final store = await TodoStore.open();
    final supabaseSync = SupabaseSyncService(store);
    final todoWidget = TodoWidgetService();
    final controller = AppController._(
      store: store,
      supabaseSync: supabaseSync,
      todoWidget: todoWidget,
    );
    await supabaseSync.load();
    await todoWidget.update(store);
    controller._scheduleNextDailyRefresh();
    return controller;
  }

  @visibleForTesting
  factory AppController.forTesting({
    required TodoStore store,
    SupabaseSyncService? supabaseSync,
  }) {
    return AppController._(
      store: store,
      supabaseSync: supabaseSync ?? SupabaseSyncService(store),
      todoWidget: TodoWidgetService(),
    );
  }

  void _onStoreChanged() {
    notifyListeners();
    unawaited(todoWidget.update(store));
  }

  @visibleForTesting
  static Duration delayUntilNextDailyRefresh(DateTime now) {
    final nextRefresh = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    return nextRefresh.difference(now);
  }

  void _scheduleNextDailyRefresh() {
    _dailyRefreshTimer?.cancel();
    if (_disposed) {
      return;
    }
    _dailyRefreshTimer = Timer(delayUntilNextDailyRefresh(DateTime.now()), () {
      unawaited(_refreshForNewDay());
    });
  }

  Future<void> _refreshForNewDay() async {
    if (_disposed) {
      return;
    }
    await store.ensureDailyRecurringTodos();
    if (_disposed) {
      return;
    }
    notifyListeners();
    _scheduleNextDailyRefresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _dailyRefreshTimer?.cancel();
    store.removeListener(_onStoreChanged);
    supabaseSync.removeListener(notifyListeners);
    supabaseSync.close();
    super.dispose();
  }
}
