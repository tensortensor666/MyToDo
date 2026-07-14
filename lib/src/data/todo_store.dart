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
import 'savings_models.dart';

class TodoStore extends ChangeNotifier {
  TodoStore._(this.device, this._db);

  static const _uuid = Uuid();
  static bool _ffiInitialized = false;

  LocalDevice device;
  final Database _db;
  List<TodoItem> _todos = const [];
  List<TodoItem> _todoHistory = const [];
  List<TodoList> _lists = const [];
  List<RecurringTemplate> _recurringTemplates = const [];
  List<SavingsPlan> _savings = const [];

  List<TodoItem> get todos => _todos;
  List<TodoItem> get todoHistory => _todoHistory;
  List<TodoList> get lists => _lists;
  List<RecurringTemplate> get recurringTemplates => _recurringTemplates;
  List<SavingsPlan> get savings => _savings;

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
    final name = prefs.getString('deviceName') ?? _defaultDeviceName(deviceId);
    await prefs.setString('deviceId', deviceId);
    await prefs.setString('deviceName', name);

    final supportDir = await getApplicationSupportDirectory();
    final dbPath = p.join(supportDir.path, 'mytodo.sqlite');
    final db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    await _ensureSchema(db);

    final store = TodoStore._(LocalDevice(deviceId: deviceId, name: name), db);
    await store.reload();
    await store.seedPrototypeDataIfEmpty();
    await store.ensureDailyRecurringTodos();
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
        version: 3,
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
        singleInstance: false,
      ),
    );
    await _ensureSchema(db);
    final store = TodoStore._(device, db);
    await store.reload();
    return store;
  }

  @visibleForTesting
  static Future<TodoStore> openPathForTesting({
    required LocalDevice device,
    required String dbPath,
  }) async {
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
        singleInstance: false,
      ),
    );
    await _ensureSchema(db);
    final store = TodoStore._(device, db);
    await store.reload();
    return store;
  }

  static Future<void> _createSchema(Database db, int version) async {
    await _ensureSchema(db);
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await _ensureSchema(db);
  }

  static Future<void> _ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  completed INTEGER NOT NULL,
  deleted INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  list_id TEXT NOT NULL DEFAULT '${TodoList.inboxId}',
  template_id TEXT,
  task_date TEXT,
  source_type TEXT NOT NULL DEFAULT '${TodoSource.manual}',
  due_at INTEGER,
  reminder_at INTEGER,
  notes TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  progress INTEGER NOT NULL DEFAULT 0
)
''');
    await _ensureTodoColumns(db);
    await db.execute('''
CREATE TABLE IF NOT EXISTS events (
  event_id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  type TEXT NOT NULL,
  todo_id TEXT NOT NULL,
  payload_json TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS todo_lists (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  is_system INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    await _ensureListColumns(db);
    await db.execute('''
CREATE TABLE IF NOT EXISTS recurring_templates (
  id TEXT PRIMARY KEY,
  list_id TEXT NOT NULL,
  title TEXT NOT NULL,
  repeat_type TEXT NOT NULL,
  start_date TEXT NOT NULL,
  archived INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  notes TEXT NOT NULL DEFAULT ''
)
''');
    await _ensureRecurringTemplateColumns(db);
    await db.execute('''
CREATE TABLE IF NOT EXISTS savings_plans (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  goal INTEGER NOT NULL DEFAULT 0,
  saved INTEGER NOT NULL DEFAULT 0,
  note TEXT NOT NULL DEFAULT '',
  due_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  deleted INTEGER NOT NULL DEFAULT 0,
  ledger TEXT NOT NULL DEFAULT '[]'
)
''');
    await _ensureSavingsColumns(db);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS events_device_seq_idx ON events(device_id, seq)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS todos_list_updated_idx ON todos(list_id, completed, due_at, updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS todos_list_sort_idx ON todos(list_id, completed, sort_order, created_at)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS todos_template_date_idx ON todos(template_id, task_date) WHERE template_id IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS recurring_templates_list_idx ON recurring_templates(list_id, archived)',
    );
    await _ensureSystemLists(db);
  }

  static Future<void> _ensureTodoColumns(DatabaseExecutor db) async {
    final columns = await _tableColumns(db, 'todos');
    if (!columns.contains('due_at')) {
      await db.execute('ALTER TABLE todos ADD COLUMN due_at INTEGER');
    }
    if (!columns.contains('reminder_at')) {
      await db.execute('ALTER TABLE todos ADD COLUMN reminder_at INTEGER');
    }
    if (!columns.contains('list_id')) {
      await db.execute(
        'ALTER TABLE todos ADD COLUMN list_id TEXT NOT NULL DEFAULT \'${TodoList.inboxId}\'',
      );
    }
    if (!columns.contains('template_id')) {
      await db.execute('ALTER TABLE todos ADD COLUMN template_id TEXT');
    }
    if (!columns.contains('task_date')) {
      await db.execute('ALTER TABLE todos ADD COLUMN task_date TEXT');
    }
    if (!columns.contains('source_type')) {
      await db.execute(
        'ALTER TABLE todos ADD COLUMN source_type TEXT NOT NULL DEFAULT \'${TodoSource.manual}\'',
      );
    }
    if (!columns.contains('important')) {
      await db.execute(
        'ALTER TABLE todos ADD COLUMN important INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columns.contains('notes')) {
      await db.execute(
        'ALTER TABLE todos ADD COLUMN notes TEXT NOT NULL DEFAULT \'\'',
      );
    }
    if (!columns.contains('sort_order')) {
      await db.execute(
        'ALTER TABLE todos ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('UPDATE todos SET sort_order = created_at');
    }
    if (!columns.contains('progress')) {
      await db.execute(
        'ALTER TABLE todos ADD COLUMN progress INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  static Future<void> _ensureListColumns(DatabaseExecutor db) async {
    final columns = await _tableColumns(db, 'todo_lists');
    if (!columns.contains('color')) {
      await db.execute('ALTER TABLE todo_lists ADD COLUMN color INTEGER');
    }
  }

  static Future<void> _ensureRecurringTemplateColumns(
    DatabaseExecutor db,
  ) async {
    final columns = await _tableColumns(db, 'recurring_templates');
    if (!columns.contains('notes')) {
      await db.execute(
        'ALTER TABLE recurring_templates ADD COLUMN notes TEXT NOT NULL DEFAULT \'\'',
      );
    }
  }

  static Future<void> _ensureSavingsColumns(DatabaseExecutor db) async {
    final columns = await _tableColumns(db, 'savings_plans');
    if (columns.isEmpty) {
      return;
    }
    if (!columns.contains('deleted')) {
      await db.execute(
        'ALTER TABLE savings_plans ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columns.contains('ledger')) {
      await db.execute(
        'ALTER TABLE savings_plans ADD COLUMN ledger TEXT NOT NULL DEFAULT \'[]\'',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS savings_plans_deleted_idx ON savings_plans(deleted, sort_order, created_at)',
    );
  }

  static Future<Set<String>> _tableColumns(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    return rows.map((row) => row['name']).whereType<String>().toSet();
  }

  static Future<void> _ensureSystemLists(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'todo_lists',
      TodoList(
        id: TodoList.inboxId,
        name: '收件箱',
        sortOrder: 0,
        isSystem: true,
        createdAt: now,
        updatedAt: now,
      ).toDb(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _removeLegacyDailySystemList(db, now);
  }

  static Future<void> _removeLegacyDailySystemList(
    DatabaseExecutor db,
    int timestamp,
  ) async {
    await db.update(
      'todos',
      {'list_id': TodoList.inboxId, 'updated_at': timestamp},
      where: 'list_id = ?',
      whereArgs: [TodoList.dailyId],
    );
    await db.update(
      'recurring_templates',
      {'list_id': TodoList.inboxId, 'updated_at': timestamp},
      where: 'list_id = ?',
      whereArgs: [TodoList.dailyId],
    );
    await db.delete(
      'todo_lists',
      where: 'id = ? AND is_system = 1',
      whereArgs: [TodoList.dailyId],
    );
  }

  static String _defaultDeviceName(String deviceId) {
    final suffix = deviceId.substring(0, 6);
    try {
      return '${Platform.localHostname}-$suffix';
    } catch (_) {
      return 'MyTodo-$suffix';
    }
  }

  Future<void> updateDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == device.name) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deviceName', trimmed);
    device = LocalDevice(deviceId: device.deviceId, name: trimmed);
    notifyListeners();
  }

  Future<void> reload() async {
    await _ensureSystemLists(_db);
    final listRows = await _db.query(
      'todo_lists',
      orderBy: 'sort_order ASC, created_at ASC',
    );
    final templateRows = await _db.query(
      'recurring_templates',
      orderBy: 'archived ASC, created_at ASC',
    );
    final historyRows = await _db.query(
      'todos',
      orderBy:
          'deleted ASC, completed ASC, sort_order ASC, created_at ASC, updated_at DESC',
    );
    final rows = await _db.query(
      'todos',
      where: 'deleted = 0',
      orderBy: 'completed ASC, sort_order ASC, created_at ASC, updated_at DESC',
    );
    final savingsRows = await _db.query(
      'savings_plans',
      where: 'deleted = 0',
      orderBy: 'sort_order ASC, created_at ASC',
    );
    _lists = listRows.map(TodoList.fromDb).toList(growable: false);
    _recurringTemplates = templateRows
        .map(RecurringTemplate.fromDb)
        .toList(growable: false);
    _todoHistory = historyRows.map(TodoItem.fromDb).toList(growable: false);
    _todos = rows.map(TodoItem.fromDb).toList(growable: false);
    _savings = savingsRows.map(SavingsPlan.fromDb).toList(growable: false);
    notifyListeners();
  }

  @visibleForTesting
  Future<bool> seedPrototypeDataIfEmpty({DateTime? now}) async {
    final hasUserData =
        _todoHistory.isNotEmpty ||
        _lists.any((list) => !list.isSystem) ||
        _recurringTemplates.isNotEmpty ||
        _savings.isNotEmpty;
    if (hasUserData) {
      return false;
    }

    final effectiveNow = now ?? DateTime.now();
    final today = DateTime(
      effectiveNow.year,
      effectiveNow.month,
      effectiveNow.day,
    );
    final todayTaskDate = _formatTaskDate(today);

    int at(int month, int day, int hour, int minute) {
      return DateTime(
        effectiveNow.year,
        month,
        day,
        hour,
        minute,
      ).millisecondsSinceEpoch;
    }

    int todayAt(int hour, int minute) {
      return DateTime(
        today.year,
        today.month,
        today.day,
        hour,
        minute,
      ).millisecondsSinceEpoch;
    }

    int dueDate(int year, int month, int day) {
      return DateTime(year, month, day, 23, 59, 59).millisecondsSinceEpoch;
    }

    int ledgerDate(int month, int day) {
      return DateTime(effectiveNow.year, month, day, 12).millisecondsSinceEpoch;
    }

    final workList = TodoList(
      id: 'prototype-work',
      name: '工作',
      sortOrder: 1000,
      isSystem: false,
      createdAt: at(6, 27, 8, 0),
      updatedAt: at(6, 27, 8, 0),
      color: 0xFF5F7F62,
    );
    final lifeList = TodoList(
      id: 'prototype-life',
      name: '生活',
      sortOrder: 2000,
      isSystem: false,
      createdAt: at(6, 27, 8, 1),
      updatedAt: at(6, 27, 8, 1),
      color: 0xFFC96442,
    );

    final prototypeTodos = <TodoItem>[
      TodoItem(
        id: 'prototype-task-weekly-shopping',
        title: '整理周末采购清单',
        completed: false,
        deleted: false,
        createdAt: at(6, 27, 8, 30),
        updatedAt: at(6, 27, 8, 30),
        sortOrder: 1000,
        listId: TodoList.inboxId,
        taskDate: todayTaskDate,
        dueAt: todayAt(18, 0),
        important: true,
        notes: '采购清单已经整理到笔记里，优先确认预算和缺货项。',
      ),
      TodoItem(
        id: 'prototype-task-sync-devices',
        title: '同步 Windows 和 Android 设备',
        completed: false,
        deleted: false,
        createdAt: at(6, 27, 9, 10),
        updatedAt: at(6, 27, 9, 10),
        sortOrder: 2000,
        listId: workList.id,
        taskDate: todayTaskDate,
        reminderAt: todayAt(20, 0),
        notes: '检查 Windows 和 Android 端是否都能完成拉取与推送。',
      ),
      TodoItem(
        id: 'prototype-task-overdue-invoice',
        title: '处理过期发票',
        completed: false,
        deleted: false,
        createdAt: at(6, 26, 14, 20),
        updatedAt: at(6, 26, 14, 20),
        sortOrder: 3000,
        listId: workList.id,
        taskDate: todayTaskDate,
        dueAt: at(6, 26, 18, 0),
        important: true,
        notes: '补开票信息并记录处理结果。',
      ),
      TodoItem(
        id: 'prototype-task-update-check',
        title: '检查应用内更新页面',
        completed: true,
        deleted: false,
        createdAt: at(6, 27, 10, 50),
        updatedAt: todayAt(11, 32),
        sortOrder: 4000,
        listId: TodoList.inboxId,
        taskDate: todayTaskDate,
        dueAt: todayAt(11, 30),
        notes: '检查安装包更新入口和下载镜像文案。',
        progress: 100,
      ),
    ];

    final prototypeSavings = <SavingsPlan>[
      SavingsPlan(
        id: 'prototype-savings-emergency',
        name: '应急备用金',
        goal: 20000,
        saved: 7000,
        note: '目标 3 个月生活费',
        dueAt: dueDate(2026, 9, 30),
        createdAt: at(6, 18, 12, 0),
        updatedAt: at(7, 2, 12, 0),
        sortOrder: 1000,
        ledger: [
          SavingsLedgerEntry(
            dateMs: ledgerDate(6, 18),
            amount: 2000,
            note: '月初结余转入',
          ),
          SavingsLedgerEntry(
            dateMs: ledgerDate(6, 25),
            amount: 3000,
            note: '奖金到账',
          ),
          SavingsLedgerEntry(
            dateMs: ledgerDate(7, 2),
            amount: 2000,
            note: '每月固定存入',
          ),
        ],
      ),
      SavingsPlan(
        id: 'prototype-savings-travel',
        name: '旅行基金',
        goal: 15000,
        saved: 2000,
        note: '目标 9 月前攒齐',
        dueAt: dueDate(2026, 11, 30),
        createdAt: at(7, 5, 12, 0),
        updatedAt: at(7, 8, 12, 0),
        sortOrder: 2000,
        ledger: [
          SavingsLedgerEntry(
            dateMs: ledgerDate(7, 5),
            amount: 1500,
            note: '压岁钱转入',
          ),
          SavingsLedgerEntry(
            dateMs: ledgerDate(7, 8),
            amount: 500,
            note: '零钱存入',
          ),
        ],
      ),
      SavingsPlan(
        id: 'prototype-savings-device',
        name: '新设备款',
        goal: 8000,
        saved: 8000,
        note: '目标已达成',
        createdAt: at(6, 20, 12, 0),
        updatedAt: at(7, 1, 12, 0),
        sortOrder: 3000,
        ledger: [
          SavingsLedgerEntry(
            dateMs: ledgerDate(6, 20),
            amount: 3000,
            note: '首笔',
          ),
          SavingsLedgerEntry(
            dateMs: ledgerDate(7, 1),
            amount: 5000,
            note: '尾款凑齐',
          ),
        ],
      ),
    ];

    await _writeLocalEntityEvents([
      _PendingEntityEvent(
        type: 'list.upsert',
        entityId: workList.id,
        payload: workList.toJson(),
      ),
      _PendingEntityEvent(
        type: 'list.upsert',
        entityId: lifeList.id,
        payload: lifeList.toJson(),
      ),
      for (final todo in prototypeTodos)
        _PendingEntityEvent(
          type: 'todo.upsert',
          entityId: todo.id,
          payload: todo.toJson(),
        ),
      for (final plan in prototypeSavings)
        _PendingEntityEvent(
          type: 'savings.upsert',
          entityId: plan.id,
          payload: plan.toJson(),
        ),
    ]);
    return true;
  }

  TodoList? listById(String id) {
    for (final list in _lists) {
      if (list.id == id) {
        return list;
      }
    }
    return null;
  }

  RecurringTemplate? recurringTemplateById(String? id) {
    if (id == null) {
      return null;
    }
    for (final template in _recurringTemplates) {
      if (template.id == id) {
        return template;
      }
    }
    return null;
  }

  List<TodoItem> visibleTodosForList(String listId) {
    switch (listId) {
      case TodoList.viewMyDayId:
        final today = _formatTaskDate(DateTime.now());
        final startOfDay = _startOfDayMs(DateTime.now());
        final endOfDay = _endOfDayMs(DateTime.now());
        return _todos
            .where((todo) {
              if (todo.taskDate == today) {
                return true;
              }
              final due = todo.dueAt;
              return due != null && due >= startOfDay && due <= endOfDay;
            })
            .toList(growable: false);
      case TodoList.viewImportantId:
        return _todos.where((todo) => todo.important).toList(growable: false);
      case TodoList.viewPlannedId:
        final planned = _todos.where((todo) => todo.dueAt != null).toList();
        planned.sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
        return planned;
      case TodoList.inboxId:
        return _todos;
      default:
        return _todos
            .where((todo) => todo.listId == listId)
            .toList(growable: false);
    }
  }

  int activeCountFor(String listId) {
    return visibleTodosForList(listId).where((todo) => !todo.completed).length;
  }

  List<TodoItem> searchTodos(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _todoHistory;
    }
    return _todoHistory
        .where(
          (todo) =>
              todo.title.toLowerCase().contains(normalized) ||
              todo.notes.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  Future<TodoList> createTodoList(String name, {int? color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('List name cannot be empty');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final sortOrder = _lists.isEmpty ? 0 : _lists.last.sortOrder + 1;
    final list = TodoList(
      id: _uuid.v4(),
      name: trimmed,
      sortOrder: sortOrder,
      isSystem: false,
      createdAt: now,
      updatedAt: now,
      color: color,
    );
    await _writeLocalEntityEvent('list.upsert', list.id, list.toJson());
    return list;
  }

  Future<void> renameTodoList(TodoList list, String name) async {
    if (list.isSystem) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == list.name) {
      return;
    }
    await _writeLocalEntityEvent(
      'list.upsert',
      list.id,
      list
          .copyWith(
            name: trimmed,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          )
          .toJson(),
    );
  }

  Future<void> deleteTodoList(TodoList list) async {
    if (list.isSystem) {
      return;
    }
    await _writeLocalEntityEvent('list.delete', list.id, list.toJson());
  }

  Future<RecurringTemplate> createRecurringTemplate(
    String title, {
    required String listId,
    String notes = '',
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Template title cannot be empty');
    }
    final now = DateTime.now();
    final template = RecurringTemplate(
      id: _uuid.v4(),
      listId: listId,
      title: trimmed,
      repeatType: RepeatType.daily,
      startDate: _formatTaskDate(now),
      archived: false,
      createdAt: now.millisecondsSinceEpoch,
      updatedAt: now.millisecondsSinceEpoch,
      notes: notes.trim(),
    );
    await _writeLocalEntityEvent(
      'template.upsert',
      template.id,
      template.toJson(),
    );
    await ensureDailyRecurringTodos(now: now);
    return template;
  }

  Future<void> updateRecurringTemplate(
    RecurringTemplate template, {
    required String title,
    required String listId,
    String? notes,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final updated = template.copyWith(
      title: trimmed,
      listId: listId,
      notes: notes?.trim() ?? template.notes,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _writeLocalEntityEvent(
      'template.upsert',
      updated.id,
      updated.toJson(),
    );
  }

  Future<void> archiveRecurringTemplate(RecurringTemplate template) async {
    if (template.archived) {
      return;
    }
    final archived = template.copyWith(
      archived: true,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _writeLocalEntityEvent(
      'template.upsert',
      archived.id,
      archived.toJson(),
    );
  }

  Future<void> ensureDailyRecurringTodos({DateTime? now}) async {
    final effectiveNow = now ?? DateTime.now();
    final today = _formatTaskDate(effectiveNow);
    var inserted = false;
    await _db.transaction((txn) async {
      await _ensureSystemLists(txn);
      final templateRows = await txn.query(
        'recurring_templates',
        where: 'archived = 0 AND repeat_type = ? AND start_date <= ?',
        whereArgs: [RepeatType.daily, today],
      );
      for (final row in templateRows) {
        final template = RecurringTemplate.fromDb(row);
        final existing = Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COUNT(*) FROM todos WHERE template_id = ? AND task_date = ?',
            [template.id, today],
          ),
        );
        if (existing != null && existing > 0) {
          continue;
        }
        final timestamp = effectiveNow.millisecondsSinceEpoch;
        final todo = TodoItem(
          id: _uuid.v4(),
          title: template.title,
          completed: false,
          deleted: false,
          createdAt: timestamp,
          updatedAt: timestamp,
          listId: template.listId,
          templateId: template.id,
          taskDate: today,
          sourceType: TodoSource.recurring,
          notes: template.notes,
          sortOrder: await _nextTodoSortOrder(txn, template.listId),
        );
        await txn.insert('todos', todo.toDb());
        inserted = true;
      }
    });
    if (inserted) {
      await reload();
    }
  }

  Future<void> createTodo(
    String title, {
    String listId = TodoList.inboxId,
    int? dueAt,
    int? reminderAt,
    bool important = false,
    String notes = '',
    int progress = 0,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final sortOrder = await _nextTodoSortOrder(_db, listId);
    final todo = TodoItem(
      id: _uuid.v4(),
      title: trimmed,
      completed: false,
      deleted: false,
      createdAt: now,
      updatedAt: now,
      listId: listId,
      dueAt: dueAt,
      reminderAt: reminderAt,
      important: important,
      notes: notes.trim(),
      sortOrder: sortOrder,
      progress: progress.clamp(0, 100),
    );
    await _writeLocalTodoEvent('todo.upsert', todo);
  }

  Future<void> updateTodo(
    TodoItem todo, {
    required String title,
    required int? dueAt,
    required int? reminderAt,
    required String listId,
    bool? important,
    String? notes,
    int? progress,
    bool detachFromRecurringTemplate = false,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final nextImportant = important ?? todo.important;
    final nextNotes = notes?.trim() ?? todo.notes;
    final nextProgress = progress == null
        ? todo.progress
        : progress.clamp(0, 100);
    final recurrenceChanged =
        detachFromRecurringTemplate &&
        (todo.templateId != null ||
            todo.taskDate != null ||
            todo.sourceType != TodoSource.manual);
    if (trimmed == todo.title &&
        dueAt == todo.dueAt &&
        reminderAt == todo.reminderAt &&
        listId == todo.listId &&
        nextImportant == todo.important &&
        nextNotes == todo.notes &&
        nextProgress == todo.progress &&
        !recurrenceChanged) {
      return;
    }
    final sortOrder = listId == todo.listId
        ? todo.sortOrder
        : await _nextTodoSortOrder(_db, listId);
    var updated = todo.copyWith(
      title: trimmed,
      listId: listId,
      dueAt: dueAt,
      reminderAt: reminderAt,
      important: nextImportant,
      notes: nextNotes,
      progress: nextProgress,
      sortOrder: sortOrder,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (detachFromRecurringTemplate) {
      updated = updated.copyWith(
        templateId: null,
        taskDate: null,
        sourceType: TodoSource.manual,
      );
    }
    await _writeLocalTodoEvent('todo.upsert', updated);
  }

  Future<void> cancelTodoRecurrence(
    TodoItem todo,
    RecurringTemplate template, {
    required String title,
    required int? dueAt,
    required int? reminderAt,
    required String listId,
    required String notes,
  }) async {
    if (todo.templateId != template.id) {
      throw ArgumentError('Todo does not belong to the recurring template');
    }
    await archiveRecurringTemplate(template);
    await updateTodo(
      todo,
      title: title,
      dueAt: dueAt,
      reminderAt: reminderAt,
      listId: listId,
      notes: notes,
      detachFromRecurringTemplate: true,
    );
  }

  Future<void> setCompleted(TodoItem todo, bool completed) async {
    final nextProgress = completed
        ? 100
        : (todo.progress >= 100 ? 80 : todo.progress);
    await _writeLocalTodoEvent(
      'todo.upsert',
      todo.copyWith(
        completed: completed,
        progress: nextProgress,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> setProgress(TodoItem todo, int progress) async {
    final clamped = progress.clamp(0, 100);
    if (clamped == todo.progress && (clamped == 100) == todo.completed) {
      return;
    }
    final nextCompleted = clamped >= 100;
    await _writeLocalTodoEvent(
      'todo.upsert',
      todo.copyWith(
        progress: clamped,
        completed: nextCompleted,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> setImportant(TodoItem todo, bool important) async {
    if (todo.important == important) {
      return;
    }
    await _writeLocalTodoEvent(
      'todo.upsert',
      todo.copyWith(
        important: important,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> setListColor(TodoList list, int? color) async {
    if (list.isSystem || list.color == color) {
      return;
    }
    await _writeLocalEntityEvent(
      'list.upsert',
      list.id,
      list
          .copyWith(
            color: color,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          )
          .toJson(),
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

  Future<void> reorderTodos(List<TodoItem> orderedTodos) async {
    if (orderedTodos.length < 2) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = <TodoItem>[];
    for (var index = 0; index < orderedTodos.length; index++) {
      final todo = orderedTodos[index];
      final sortOrder = (index + 1) * 1000;
      if (todo.sortOrder != sortOrder) {
        updates.add(
          todo.copyWith(sortOrder: sortOrder, updatedAt: now + index),
        );
      }
    }
    if (updates.isEmpty) {
      return;
    }
    await _writeLocalTodoEvents('todo.upsert', updates);
  }

  // ── 存钱计划 ───────────────────────────────────────────
  Future<void> _writeSavingsEvent(String type, SavingsPlan plan) async {
    await _writeLocalEntityEvent(type, plan.id, plan.toJson());
  }

  Future<int> _nextSavingsSortOrder() async {
    final rows = await _db.rawQuery(
      'SELECT MAX(sort_order) AS max_sort FROM savings_plans WHERE deleted = 0',
    );
    return (Sqflite.firstIntValue(rows) ?? 0) + 1000;
  }

  Future<SavingsPlan> createSavingsPlan(
    String name, {
    required int goal,
    int firstDeposit = 0,
    int? dueAt,
    String note = '',
  }) async {
    final trimmed = name.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    final sortOrder = await _nextSavingsSortOrder();
    final first = firstDeposit > 0 ? firstDeposit : 0;
    final initialLedger = first > 0
        ? [SavingsLedgerEntry(dateMs: now, amount: first, note: '首笔')]
        : const <SavingsLedgerEntry>[];
    final plan = SavingsPlan(
      id: _uuid.v4(),
      name: trimmed.isEmpty ? '存钱计划' : trimmed,
      goal: goal < 0 ? 0 : goal,
      saved: first,
      note: note.trim(),
      dueAt: dueAt,
      createdAt: now,
      updatedAt: now,
      sortOrder: sortOrder,
      ledger: initialLedger,
    );
    await _writeSavingsEvent('savings.upsert', plan);
    return savings.firstWhere((p) => p.id == plan.id, orElse: () => plan);
  }

  Future<void> updateSavingsPlan(
    SavingsPlan plan, {
    required String name,
    required int goal,
    int? dueAt,
    String? note,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final nextNote = note?.trim() ?? plan.note;
    final nextGoal = goal < 0 ? 0 : goal;
    if (trimmed == plan.name &&
        nextGoal == plan.goal &&
        dueAt == plan.dueAt &&
        nextNote == plan.note) {
      return;
    }
    await _writeSavingsEvent(
      'savings.upsert',
      plan.copyWith(
        name: trimmed,
        goal: nextGoal,
        note: nextNote,
        dueAt: dueAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> deleteSavingsPlan(SavingsPlan plan) async {
    await _writeSavingsEvent(
      'savings.delete',
      plan.copyWith(
        deleted: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> depositSavings(
    SavingsPlan plan,
    int amount, {
    String? note,
  }) async {
    final add = amount.round();
    if (add <= 0) {
      return;
    }
    final before = plan.saved;
    final cap = plan.goal > 0 ? plan.goal : add + before;
    final after = (before + add).clamp(0, cap).toInt();
    final actual = after - before;
    if (actual == 0) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final ledger = [
      SavingsLedgerEntry(
        dateMs: now,
        amount: actual,
        note: note?.trim() ?? '存入',
      ),
      ...plan.ledger,
    ];
    await _writeSavingsEvent(
      'savings.upsert',
      plan.copyWith(saved: after, ledger: ledger, updatedAt: now),
    );
  }

  Future<void> withdrawSavings(
    SavingsPlan plan,
    int amount, {
    String? note,
  }) async {
    final sub = amount.round();
    if (sub <= 0) {
      return;
    }
    final before = plan.saved;
    final after = (before - sub).clamp(0, before).toInt();
    final actual = before - after;
    if (actual == 0) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final ledger = [
      SavingsLedgerEntry(
        dateMs: now,
        amount: -actual,
        note: note?.trim() ?? '取出',
      ),
      ...plan.ledger,
    ];
    await _writeSavingsEvent(
      'savings.upsert',
      plan.copyWith(saved: after, ledger: ledger, updatedAt: now),
    );
  }

  Future<void> _writeLocalTodoEvent(String type, TodoItem todo) async {
    await _writeLocalEntityEvent(type, todo.id, todo.toJson());
  }

  Future<void> _writeLocalTodoEvents(String type, List<TodoItem> todos) async {
    await _writeLocalEntityEvents([
      for (final todo in todos)
        _PendingEntityEvent(
          type: type,
          entityId: todo.id,
          payload: todo.toJson(),
        ),
    ]);
  }

  Future<void> _writeLocalEntityEvent(
    String type,
    String entityId,
    Map<String, Object?> payload,
  ) async {
    await _writeLocalEntityEvents([
      _PendingEntityEvent(type: type, entityId: entityId, payload: payload),
    ]);
  }

  Future<void> _writeLocalEntityEvents(
    List<_PendingEntityEvent> pendingEvents,
  ) async {
    if (pendingEvents.isEmpty) {
      return;
    }
    final seq = await _nextLocalSeq();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final events = [
      for (var index = 0; index < pendingEvents.length; index++)
        TodoEvent(
          eventId: _uuid.v4(),
          deviceId: device.deviceId,
          seq: seq + index,
          timestamp: timestamp + index,
          type: pendingEvents[index].type,
          todoId: pendingEvents[index].entityId,
          payload: pendingEvents[index].payload,
        ),
    ];
    await _db.transaction((txn) async {
      for (final event in events) {
        await txn.insert('events', event.toDb());
        await _applyEventInTransaction(txn, event);
      }
    });
    await reload();
  }

  Future<int> _nextTodoSortOrder(DatabaseExecutor db, String listId) async {
    final rows = await db.rawQuery(
      'SELECT MAX(sort_order) AS max_sort FROM todos WHERE deleted = 0 AND list_id = ?',
      [listId],
    );
    final maxSort = rows.first['max_sort'] as int?;
    return (maxSort ?? 0) + 1000;
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
    return rows
        .map(TodoEvent.fromDb)
        .where((event) => event.seq > (clock[event.deviceId] ?? 0))
        .toList(growable: false);
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
    switch (event.type) {
      case 'todo.upsert':
      case 'todo.delete':
        await _applyTodoEventInTransaction(txn, event);
        return;
      case 'list.upsert':
        await _applyListUpsertInTransaction(txn, event);
        return;
      case 'list.delete':
        await _applyListDeleteInTransaction(txn, event);
        return;
      case 'template.upsert':
      case 'template.delete':
        await _applyTemplateEventInTransaction(txn, event);
        return;
      case 'savings.upsert':
      case 'savings.delete':
        await _applySavingsEventInTransaction(txn, event);
        return;
    }
  }

  Future<void> _applySavingsEventInTransaction(
    Transaction txn,
    TodoEvent event,
  ) async {
    final incoming = SavingsPlan.fromJson(event.payload);
    final existingRows = await txn.query(
      'savings_plans',
      where: 'id = ?',
      whereArgs: [incoming.id],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      final existing = SavingsPlan.fromDb(existingRows.first);
      if (incoming.updatedAt < existing.updatedAt) {
        return;
      }
    }
    await txn.insert(
      'savings_plans',
      incoming.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _applyTodoEventInTransaction(
    Transaction txn,
    TodoEvent event,
  ) async {
    final parsed = TodoItem.fromJson(event.payload);
    final incoming = parsed.listId == TodoList.dailyId
        ? parsed.copyWith(listId: TodoList.inboxId)
        : parsed;
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

  Future<void> _applyListUpsertInTransaction(
    Transaction txn,
    TodoEvent event,
  ) async {
    final incoming = TodoList.fromJson(event.payload);
    if (incoming.id == TodoList.dailyId && incoming.isSystem) {
      return;
    }
    final existingRows = await txn.query(
      'todo_lists',
      where: 'id = ?',
      whereArgs: [incoming.id],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      final existing = TodoList.fromDb(existingRows.first);
      if (incoming.updatedAt < existing.updatedAt) {
        return;
      }
    }
    await txn.insert(
      'todo_lists',
      incoming.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _applyListDeleteInTransaction(
    Transaction txn,
    TodoEvent event,
  ) async {
    final incoming = TodoList.fromJson(event.payload);
    if (incoming.isSystem) {
      return;
    }
    final existingRows = await txn.query(
      'todo_lists',
      where: 'id = ?',
      whereArgs: [incoming.id],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      final existing = TodoList.fromDb(existingRows.first);
      if (incoming.updatedAt < existing.updatedAt) {
        return;
      }
    }
    await txn.update(
      'todos',
      {'list_id': TodoList.inboxId},
      where: 'list_id = ?',
      whereArgs: [incoming.id],
    );
    await txn.update(
      'recurring_templates',
      {'list_id': TodoList.inboxId, 'updated_at': event.timestamp},
      where: 'list_id = ?',
      whereArgs: [incoming.id],
    );
    await txn.delete('todo_lists', where: 'id = ?', whereArgs: [incoming.id]);
  }

  Future<void> _applyTemplateEventInTransaction(
    Transaction txn,
    TodoEvent event,
  ) async {
    final parsed = RecurringTemplate.fromJson(event.payload);
    final incoming = parsed.listId == TodoList.dailyId
        ? parsed.copyWith(listId: TodoList.inboxId)
        : parsed;
    final existingRows = await txn.query(
      'recurring_templates',
      where: 'id = ?',
      whereArgs: [incoming.id],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      final existing = RecurringTemplate.fromDb(existingRows.first);
      if (incoming.updatedAt < existing.updatedAt) {
        return;
      }
    }
    await txn.insert(
      'recurring_templates',
      incoming.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> exportBackup() async {
    final supportDir = await getApplicationSupportDirectory();
    final now = DateTime.now();
    final fileName = 'mytodo-backup-${_backupTimestamp(now)}.json';
    final file = File(p.join(supportDir.path, fileName));
    final data = {
      'app': 'mytodo',
      'version': 2,
      'generatedAt': now.toIso8601String(),
      'device': {'deviceId': device.deviceId, 'name': device.name},
      'lists': _lists.map((item) => item.toJson()).toList(),
      'recurringTemplates': _recurringTemplates
          .map((item) => item.toJson())
          .toList(),
      'todos': _todoHistory.map((todo) => todo.toJson()).toList(),
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

  static String _formatTaskDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  static int _startOfDayMs(DateTime value) {
    return DateTime(value.year, value.month, value.day).millisecondsSinceEpoch;
  }

  static int _endOfDayMs(DateTime value) {
    return DateTime(
      value.year,
      value.month,
      value.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;
  }
}

class _PendingEntityEvent {
  const _PendingEntityEvent({
    required this.type,
    required this.entityId,
    required this.payload,
  });

  final String type;
  final String entityId;
  final Map<String, Object?> payload;
}
