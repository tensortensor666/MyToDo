import 'package:flutter/foundation.dart';

import 'data/todo_store.dart';
import 'sync/sync_service.dart';

class AppController extends ChangeNotifier {
  AppController._({required this.store, required this.sync}) {
    store.addListener(notifyListeners);
    sync.addListener(notifyListeners);
  }

  final TodoStore store;
  final SyncService sync;

  static Future<AppController> create() async {
    final store = await TodoStore.open();
    final sync = SyncService(store);
    final controller = AppController._(store: store, sync: sync);
    await sync.start();
    return controller;
  }

  @override
  void dispose() {
    store.removeListener(notifyListeners);
    sync.removeListener(notifyListeners);
    sync.stop();
    super.dispose();
  }
}
