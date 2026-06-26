import 'dart:convert';

class TodoItem {
  const TodoItem({
    required this.id,
    required this.title,
    required this.completed,
    required this.deleted,
    required this.createdAt,
    required this.updatedAt,
    this.dueAt,
    this.reminderAt,
  });

  final String id;
  final String title;
  final bool completed;
  final bool deleted;
  final int createdAt;
  final int updatedAt;
  final int? dueAt;
  final int? reminderAt;

  TodoItem copyWith({
    String? title,
    bool? completed,
    bool? deleted,
    int? updatedAt,
    Object? dueAt = _notSet,
    Object? reminderAt = _notSet,
  }) {
    return TodoItem(
      id: id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
      deleted: deleted ?? this.deleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dueAt: identical(dueAt, _notSet) ? this.dueAt : dueAt as int?,
      reminderAt: identical(reminderAt, _notSet)
          ? this.reminderAt
          : reminderAt as int?,
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
      'dueAt': dueAt,
      'reminderAt': reminderAt,
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
      dueAt: json['dueAt'] as int?,
      reminderAt: json['reminderAt'] as int?,
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
      'due_at': dueAt,
      'reminder_at': reminderAt,
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
      dueAt: row['due_at'] as int?,
      reminderAt: row['reminder_at'] as int?,
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
  const LocalDevice({
    required this.deviceId,
    required this.name,
    required this.token,
  });

  final String deviceId;
  final String name;
  final String token;
}

class TrustedDevice {
  const TrustedDevice({
    required this.deviceId,
    required this.name,
    required this.baseUrl,
    required this.token,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String name;
  final String baseUrl;
  final String token;
  final int lastSeenAt;

  Map<String, Object?> toDb() {
    return {
      'device_id': deviceId,
      'name': name,
      'base_url': baseUrl,
      'token': token,
      'last_seen_at': lastSeenAt,
    };
  }

  factory TrustedDevice.fromDb(Map<String, Object?> row) {
    return TrustedDevice(
      deviceId: row['device_id'] as String,
      name: row['name'] as String,
      baseUrl: row['base_url'] as String,
      token: row['token'] as String,
      lastSeenAt: row['last_seen_at'] as int,
    );
  }
}
