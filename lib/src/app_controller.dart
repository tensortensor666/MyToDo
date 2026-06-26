import 'package:flutter/foundation.dart';

import 'data/todo_store.dart';
import 'sync/sync_service.dart';
import 'sync/supabase_sync_service.dart';

class AppController extends ChangeNotifier {
  AppController._({
    required this.store,
    required this.sync,
    required this.supabaseSync,
  }) {
    store.addListener(notifyListeners);
    sync.addListener(notifyListeners);
    supabaseSync.addListener(notifyListeners);
  }

  final TodoStore store;
  final SyncService sync;
  final SupabaseSyncService supabaseSync;

  static Future<AppController> create() async {
    final store = await TodoStore.open();
    final sync = SyncService(store);
    final supabaseSync = SupabaseSyncService(store);
    final controller = AppController._(
      store: store,
      sync: sync,
      supabaseSync: supabaseSync,
    );
    await supabaseSync.load();
    await sync.start();
    return controller;
  }

  @visibleForTesting
  factory AppController.forTesting({
    required TodoStore store,
    required SyncService sync,
    SupabaseSyncService? supabaseSync,
  }) {
    return AppController._(
      store: store,
      sync: sync,
      supabaseSync: supabaseSync ?? SupabaseSyncService(store),
    );
  }

  @override
  void dispose() {
    store.removeListener(notifyListeners);
    sync.removeListener(notifyListeners);
    supabaseSync.removeListener(notifyListeners);
    sync.stop();
    supabaseSync.close();
    super.dispose();
  }
}
