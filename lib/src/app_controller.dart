import 'package:flutter/foundation.dart';

import 'data/todo_store.dart';
import 'sync/supabase_sync_service.dart';

class AppController extends ChangeNotifier {
  AppController._({required this.store, required this.supabaseSync}) {
    store.addListener(notifyListeners);
    supabaseSync.addListener(notifyListeners);
  }

  final TodoStore store;
  final SupabaseSyncService supabaseSync;

  static Future<AppController> create() async {
    final store = await TodoStore.open();
    final supabaseSync = SupabaseSyncService(store);
    final controller = AppController._(
      store: store,
      supabaseSync: supabaseSync,
    );
    await supabaseSync.load();
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
    );
  }

  @override
  void dispose() {
    store.removeListener(notifyListeners);
    supabaseSync.removeListener(notifyListeners);
    supabaseSync.close();
    super.dispose();
  }
}
