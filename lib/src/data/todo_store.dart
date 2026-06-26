import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'todo_models.dart';

class TodoStore extends ChangeNotifier {
  TodoStore._(this.device, this._db);

  static const _uuid = Uuid();
  static bool _ffiInitialized = false;

  final LocalDevice device;
  final Database _db;
  List<TodoItem> _todos = const [];
  List<TodoItem> _todoHistory = const [];
  List<TrustedDevice> _trustedDevices = const [];

  List<TodoItem> get todos => _todos;
  List<TodoItem> get todoHistory => _todoHistory;
  List<TrustedDevice> get trustedDevices => _trustedDevices;

  static Future<TodoStore> open() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (!_ffiInitialized) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        _ffiInitialized = true;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('deviceId') ?? _uuid.v4();
    final token = prefs.getString('pairingToken') ?? _uuid.v4();
    final name = prefs.getString('deviceName') ?? _defaultDeviceName(deviceId);
    await prefs.setString('deviceId', deviceId);
    await prefs.setString('pairingToken', token);
    await prefs.setString('deviceName', name);

    final supportDir = await getApplicationSupportDirectory();
    final dbPath = p.join(supportDir.path, 'mytodo.sqlite');
    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );

    final store = TodoStore._(
      LocalDevice(deviceId: deviceId, name: name, token: token),
      db,
    );
    await store.reload();
    return store;
  }

  @visibleForTesting
  static Future<TodoStore> openInMemoryForTesting({
    required LocalDevice device,
  }) async {
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _createSchema,
        singleInstance: false,
      ),
    );
    final store = TodoStore._(device, db);
    await store.reload();
    return store;
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
CREATE TABLE todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  completed INTEGER NOT NULL,
  deleted INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  due_at INTEGER,
  reminder_at INTEGER
)
''');
    await db.execute('''
CREATE TABLE events (
  event_id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  type TEXT NOT NULL,
  todo_id TEXT NOT NULL,
  payload_json TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX events_device_seq_idx ON events(device_id, seq)',
    );
    await db.execute('''
CREATE TABLE trusted_devices (
  device_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  base_url TEXT NOT NULL,
  token TEXT NOT NULL,
  last_seen_at INTEGER NOT NULL
)
''');
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE todos ADD COLUMN due_at INTEGER');
      await db.execute('ALTER TABLE todos ADD COLUMN reminder_at INTEGER');
    }
  }

  static String _defaultDeviceName(String deviceId) {
    final suffix = deviceId.substring(0, 6);
    try {
      return '${Platform.localHostname}-$suffix';
    } catch (_) {
      return 'MyTodo-$suffix';
    }
  }

  Future<void> reload() async {
    final historyRows = await _db.query(
      'todos',
      orderBy:
          'deleted ASC, completed ASC, due_at IS NULL ASC, due_at ASC, updated_at DESC',
    );
    final rows = await _db.query(
      'todos',
      where: 'deleted = 0',
      orderBy: 'completed ASC, due_at IS NULL ASC, due_at ASC, updated_at DESC',
    );
    final trustedRows = await _db.query(
      'trusted_devices',
      orderBy: 'last_seen_at DESC',
    );
    _todoHistory = historyRows.map(TodoItem.fromDb).toList(growable: false);
    _todos = rows.map(TodoItem.fromDb).toList(growable: false);
    _trustedDevices = trustedRows
        .map(TrustedDevice.fromDb)
        .toList(growable: false);
    notifyListeners();
  }

  List<TodoItem> searchTodos(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _todoHistory;
    }
    return _todoHistory
        .where((todo) => todo.title.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  Future<void> createTodo(String title, {int? dueAt, int? reminderAt}) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final todo = TodoItem(
      id: _uuid.v4(),
      title: trimmed,
      completed: false,
      deleted: false,
      createdAt: now,
      updatedAt: now,
      dueAt: dueAt,
      reminderAt: reminderAt,
    );
    await _writeLocalTodoEvent('todo.upsert', todo);
  }

  Future<void> updateTodo(
    TodoItem todo, {
    required String title,
    int? dueAt,
    int? reminderAt,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (trimmed == todo.title &&
        dueAt == todo.dueAt &&
        reminderAt == todo.reminderAt) {
      return;
    }
    await _writeLocalTodoEvent(
      'todo.upsert',
      todo.copyWith(
        title: trimmed,
        dueAt: dueAt,
        reminderAt: reminderAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> setCompleted(TodoItem todo, bool completed) async {
    await _writeLocalTodoEvent(
      'todo.upsert',
      todo.copyWith(
        completed: completed,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> renameTodo(TodoItem todo, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == todo.title) {
      return;
    }
    await _writeLocalTodoEvent(
      'todo.upsert',
      todo.copyWith(
        title: trimmed,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> deleteTodo(TodoItem todo) async {
    await _writeLocalTodoEvent(
      'todo.delete',
      todo.copyWith(
        deleted: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> restoreTodo(TodoItem todo) async {
    await _writeLocalTodoEvent(
      'todo.upsert',
      todo.copyWith(
        deleted: false,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _writeLocalTodoEvent(String type, TodoItem todo) async {
    final seq = await _nextLocalSeq();
    final event = TodoEvent(
      eventId: _uuid.v4(),
      deviceId: device.deviceId,
      seq: seq,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: type,
      todoId: todo.id,
      payload: todo.toJson(),
    );
    await _db.transaction((txn) async {
      await txn.insert('events', event.toDb());
      await _applyEventInTransaction(txn, event);
    });
    await reload();
  }

  Future<int> _nextLocalSeq() async {
    final rows = await _db.rawQuery(
      'SELECT MAX(seq) AS max_seq FROM events WHERE device_id = ?',
      [device.deviceId],
    );
    final maxSeq = rows.first['max_seq'] as int?;
    return (maxSeq ?? 0) + 1;
  }

  Future<Map<String, int>> eventClock() async {
    final rows = await _db.rawQuery(
      'SELECT device_id, MAX(seq) AS max_seq FROM events GROUP BY device_id',
    );
    return {
      for (final row in rows) row['device_id'] as String: row['max_seq'] as int,
    };
  }

  Future<List<TodoEvent>> eventsAfterClock(Map<String, int> clock) async {
    final rows = await _db.query('events', orderBy: 'timestamp ASC, seq ASC');
    final events = rows
        .map(TodoEvent.fromDb)
        .where((event) {
          return event.seq > (clock[event.deviceId] ?? 0);
        })
        .toList(growable: false);
    return events;
  }

  Future<List<TodoEvent>> allEvents() async {
    final rows = await _db.query('events', orderBy: 'timestamp ASC, seq ASC');
    return rows.map(TodoEvent.fromDb).toList(growable: false);
  }

  Future<int> applyRemoteEvents(List<TodoEvent> events) async {
    var applied = 0;
    await _db.transaction((txn) async {
      for (final event in events) {
        final exists = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM events WHERE event_id = ?', [
            event.eventId,
          ]),
        );
        if (exists != 0) {
          continue;
        }
        await txn.insert('events', event.toDb());
        await _applyEventInTransaction(txn, event);
        applied++;
      }
    });
    if (applied > 0) {
      await reload();
    }
    return applied;
  }

  Future<void> _applyEventInTransaction(
    Transaction txn,
    TodoEvent event,
  ) async {
    if (event.type != 'todo.upsert' && event.type != 'todo.delete') {
      return;
    }
    final incoming = TodoItem.fromJson(event.payload);
    final existingRows = await txn.query(
      'todos',
      where: 'id = ?',
      whereArgs: [incoming.id],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      final existing = TodoItem.fromDb(existingRows.first);
      if (incoming.updatedAt < existing.updatedAt) {
        return;
      }
    }
    await txn.insert(
      'todos',
      incoming.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertTrustedDevice(TrustedDevice device) async {
    await _db.insert(
      'trusted_devices',
      device.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await reload();
  }

  TrustedDevice? trustedDeviceById(String deviceId) {
    for (final device in _trustedDevices) {
      if (device.deviceId == deviceId) {
        return device;
      }
    }
    return null;
  }

  Future<String> exportBackup() async {
    final supportDir = await getApplicationSupportDirectory();
    final now = DateTime.now();
    final fileName = 'mytodo-backup-${_backupTimestamp(now)}.json';
    final file = File(p.join(supportDir.path, fileName));
    final data = {
      'app': 'mytodo',
      'version': 1,
      'generatedAt': now.toIso8601String(),
      'device': {'deviceId': device.deviceId, 'name': device.name},
      'todos': _todoHistory.map((todo) => todo.toJson()).toList(),
      'trustedDevices': _trustedDevices.map((item) => item.toDb()).toList(),
      'events': (await allEvents()).map((event) => event.toJson()).toList(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    return file.path;
  }

  static String _backupTimestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}
