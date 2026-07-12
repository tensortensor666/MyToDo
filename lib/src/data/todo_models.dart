import 'dart:convert';

class TodoSource {
  static const manual = 'manual';
  static const recurring = 'recurring';
}

class RepeatType {
  static const daily = 'daily';
}

class TodoList {
  const TodoList({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isSystem,
    required this.createdAt,
    required this.updatedAt,
    this.color,
  });

  static const inboxId = 'system-inbox';
  static const dailyId = 'system-daily';

  static const viewMyDayId = 'view-myday';
  static const viewImportantId = 'view-important';
  static const viewPlannedId = 'view-planned';
  static const viewSavingsId = 'view-savings';

  static const virtualViewIds = <String>{
    viewMyDayId,
    viewImportantId,
    viewPlannedId,
    viewSavingsId,
  };

  final String id;
  final String name;
  final int sortOrder;
  final bool isSystem;
  final int createdAt;
  final int updatedAt;
  final int? color;

  TodoList copyWith({
    String? name,
    int? sortOrder,
    bool? isSystem,
    int? updatedAt,
    Object? color = _notSet,
  }) {
    return TodoList(
      id: id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      color: identical(color, _notSet) ? this.color : color as int?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'sortOrder': sortOrder,
      'isSystem': isSystem,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'color': color,
    };
  }

  factory TodoList.fromJson(Map<String, Object?> json) {
    return TodoList(
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: json['sortOrder'] as int,
      isSystem: json['isSystem'] as bool,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      color: json['color'] as int?,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'id': id,
      'name': name,
      'sort_order': sortOrder,
      'is_system': isSystem ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'color': color,
    };
  }

  factory TodoList.fromDb(Map<String, Object?> row) {
    return TodoList(
      id: row['id'] as String,
      name: row['name'] as String,
      sortOrder: row['sort_order'] as int,
      isSystem: (row['is_system'] as int) == 1,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      color: row['color'] as int?,
    );
  }
}

class RecurringTemplate {
  const RecurringTemplate({
    required this.id,
    required this.listId,
    required this.title,
    required this.repeatType,
    required this.startDate,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    this.notes = '',
  });

  final String id;
  final String listId;
  final String title;
  final String repeatType;
  final String startDate;
  final bool archived;
  final int createdAt;
  final int updatedAt;
  final String notes;

  RecurringTemplate copyWith({
    String? listId,
    String? title,
    String? repeatType,
    String? startDate,
    bool? archived,
    int? updatedAt,
    String? notes,
  }) {
    return RecurringTemplate(
      id: id,
      listId: listId ?? this.listId,
      title: title ?? this.title,
      repeatType: repeatType ?? this.repeatType,
      startDate: startDate ?? this.startDate,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'listId': listId,
      'title': title,
      'repeatType': repeatType,
      'startDate': startDate,
      'archived': archived,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'notes': notes,
    };
  }

  factory RecurringTemplate.fromJson(Map<String, Object?> json) {
    return RecurringTemplate(
      id: json['id'] as String,
      listId: json['listId'] as String,
      title: json['title'] as String,
      repeatType: json['repeatType'] as String,
      startDate: json['startDate'] as String,
      archived: json['archived'] as bool,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      notes: json['notes'] as String? ?? '',
    );
  }

  Map<String, Object?> toDb() {
    return {
      'id': id,
      'list_id': listId,
      'title': title,
      'repeat_type': repeatType,
      'start_date': startDate,
      'archived': archived ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'notes': notes,
    };
  }

  factory RecurringTemplate.fromDb(Map<String, Object?> row) {
    return RecurringTemplate(
      id: row['id'] as String,
      listId: row['list_id'] as String,
      title: row['title'] as String,
      repeatType: row['repeat_type'] as String,
      startDate: row['start_date'] as String,
      archived: (row['archived'] as int) == 1,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      notes: row['notes'] as String? ?? '',
    );
  }
}

class TodoItem {
  const TodoItem({
    required this.id,
    required this.title,
    required this.completed,
    required this.deleted,
    required this.createdAt,
    required this.updatedAt,
    int? sortOrder,
    this.listId = TodoList.inboxId,
    this.templateId,
    this.taskDate,
    this.sourceType = TodoSource.manual,
    this.dueAt,
    this.reminderAt,
    this.important = false,
    this.notes = '',
    this.progress = 0,
  }) : sortOrder = sortOrder ?? createdAt;

  final String id;
  final String title;
  final bool completed;
  final bool deleted;
  final int createdAt;
  final int updatedAt;
  final int sortOrder;
  final String listId;
  final String? templateId;
  final String? taskDate;
  final String sourceType;
  final int? dueAt;
  final int? reminderAt;
  final bool important;
  final String notes;
  final int progress;

  TodoItem copyWith({
    String? title,
    bool? completed,
    bool? deleted,
    int? updatedAt,
    int? sortOrder,
    String? listId,
    Object? templateId = _notSet,
    Object? taskDate = _notSet,
    String? sourceType,
    Object? dueAt = _notSet,
    Object? reminderAt = _notSet,
    bool? important,
    String? notes,
    int? progress,
  }) {
    return TodoItem(
      id: id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
      deleted: deleted ?? this.deleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      listId: listId ?? this.listId,
      templateId: identical(templateId, _notSet)
          ? this.templateId
          : templateId as String?,
      taskDate: identical(taskDate, _notSet)
          ? this.taskDate
          : taskDate as String?,
      sourceType: sourceType ?? this.sourceType,
      dueAt: identical(dueAt, _notSet) ? this.dueAt : dueAt as int?,
      reminderAt: identical(reminderAt, _notSet)
          ? this.reminderAt
          : reminderAt as int?,
      important: important ?? this.important,
      notes: notes ?? this.notes,
      progress: progress ?? this.progress,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'completed': completed,
      'deleted': deleted,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'sortOrder': sortOrder,
      'listId': listId,
      'templateId': templateId,
      'taskDate': taskDate,
      'sourceType': sourceType,
      'dueAt': dueAt,
      'reminderAt': reminderAt,
      'important': important,
      'notes': notes,
      'progress': progress,
    };
  }

  factory TodoItem.fromJson(Map<String, Object?> json) {
    return TodoItem(
      id: json['id'] as String,
      title: json['title'] as String,
      completed: json['completed'] as bool,
      deleted: json['deleted'] as bool? ?? false,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      sortOrder: json['sortOrder'] as int? ?? json['createdAt'] as int,
      listId: json['listId'] as String? ?? TodoList.inboxId,
      templateId: json['templateId'] as String?,
      taskDate: json['taskDate'] as String?,
      sourceType: json['sourceType'] as String? ?? TodoSource.manual,
      dueAt: json['dueAt'] as int?,
      reminderAt: json['reminderAt'] as int?,
      important: json['important'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'id': id,
      'title': title,
      'completed': completed ? 1 : 0,
      'deleted': deleted ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'sort_order': sortOrder,
      'list_id': listId,
      'template_id': templateId,
      'task_date': taskDate,
      'source_type': sourceType,
      'due_at': dueAt,
      'reminder_at': reminderAt,
      'important': important ? 1 : 0,
      'notes': notes,
      'progress': progress,
    };
  }

  factory TodoItem.fromDb(Map<String, Object?> row) {
    return TodoItem(
      id: row['id'] as String,
      title: row['title'] as String,
      completed: (row['completed'] as int) == 1,
      deleted: (row['deleted'] as int) == 1,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      sortOrder: row['sort_order'] as int? ?? row['created_at'] as int,
      listId: row['list_id'] as String? ?? TodoList.inboxId,
      templateId: row['template_id'] as String?,
      taskDate: row['task_date'] as String?,
      sourceType: row['source_type'] as String? ?? TodoSource.manual,
      dueAt: row['due_at'] as int?,
      reminderAt: row['reminder_at'] as int?,
      important: (row['important'] as int? ?? 0) == 1,
      notes: row['notes'] as String? ?? '',
      progress: row['progress'] as int? ?? 0,
    );
  }
}

const Object _notSet = Object();

class TodoEvent {
  const TodoEvent({
    required this.eventId,
    required this.deviceId,
    required this.seq,
    required this.timestamp,
    required this.type,
    required this.todoId,
    required this.payload,
  });

  final String eventId;
  final String deviceId;
  final int seq;
  final int timestamp;
  final String type;
  final String todoId;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() {
    return {
      'eventId': eventId,
      'deviceId': deviceId,
      'seq': seq,
      'timestamp': timestamp,
      'type': type,
      'todoId': todoId,
      'payload': payload,
    };
  }

  factory TodoEvent.fromJson(Map<String, Object?> json) {
    return TodoEvent(
      eventId: json['eventId'] as String,
      deviceId: json['deviceId'] as String,
      seq: json['seq'] as int,
      timestamp: json['timestamp'] as int,
      type: json['type'] as String,
      todoId: json['todoId'] as String,
      payload: Map<String, Object?>.from(json['payload'] as Map),
    );
  }

  Map<String, Object?> toDb() {
    return {
      'event_id': eventId,
      'device_id': deviceId,
      'seq': seq,
      'timestamp': timestamp,
      'type': type,
      'todo_id': todoId,
      'payload_json': jsonEncode(payload),
    };
  }

  factory TodoEvent.fromDb(Map<String, Object?> row) {
    return TodoEvent(
      eventId: row['event_id'] as String,
      deviceId: row['device_id'] as String,
      seq: row['seq'] as int,
      timestamp: row['timestamp'] as int,
      type: row['type'] as String,
      todoId: row['todo_id'] as String,
      payload: Map<String, Object?>.from(
        jsonDecode(row['payload_json'] as String) as Map,
      ),
    );
  }
}

class LocalDevice {
  const LocalDevice({required this.deviceId, required this.name});

  final String deviceId;
  final String name;
}
