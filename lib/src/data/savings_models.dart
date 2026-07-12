import 'dart:convert';

class SavingsLedgerEntry {
  const SavingsLedgerEntry({
    required this.dateMs,
    required this.amount,
    this.note = '',
  });

  final int dateMs;
  final int amount;
  final String note;

  SavingsLedgerEntry copyWith({int? dateMs, int? amount, String? note}) {
    return SavingsLedgerEntry(
      dateMs: dateMs ?? this.dateMs,
      amount: amount ?? this.amount,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() {
    return {'dateMs': dateMs, 'amount': amount, 'note': note};
  }

  factory SavingsLedgerEntry.fromJson(Map<String, Object?> json) {
    return SavingsLedgerEntry(
      dateMs: json['dateMs'] as int? ?? json['date'] as int? ?? 0,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      note: json['note'] as String? ?? '',
    );
  }
}

class SavingsPlan {
  const SavingsPlan({
    required this.id,
    required this.name,
    required this.goal,
    required this.saved,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
    required this.ledger,
    this.note = '',
    this.dueAt,
    this.deleted = false,
  });

  final String id;
  final String name;
  final int goal;
  final int saved;
  final String note;
  final int? dueAt;
  final int createdAt;
  final int updatedAt;
  final int sortOrder;
  final bool deleted;
  final List<SavingsLedgerEntry> ledger;

  bool get isDone => goal > 0 && saved >= goal;

  int get remaining => goal > 0 ? (goal - saved).clamp(0, goal) : 0;

  int get percent {
    if (goal <= 0) return 0;
    return ((saved / goal) * 100).round().clamp(0, 100);
  }

  SavingsPlan copyWith({
    String? name,
    int? goal,
    int? saved,
    String? note,
    Object? dueAt = _notSet,
    int? updatedAt,
    int? sortOrder,
    bool? deleted,
    List<SavingsLedgerEntry>? ledger,
  }) {
    return SavingsPlan(
      id: id,
      name: name ?? this.name,
      goal: goal ?? this.goal,
      saved: saved ?? this.saved,
      note: note ?? this.note,
      dueAt: identical(dueAt, _notSet) ? this.dueAt : dueAt as int?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      deleted: deleted ?? this.deleted,
      ledger: ledger ?? this.ledger,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'goal': goal,
      'saved': saved,
      'note': note,
      'dueAt': dueAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'sortOrder': sortOrder,
      'deleted': deleted,
      'ledger': [for (final e in ledger) e.toJson()],
    };
  }

  factory SavingsPlan.fromJson(Map<String, Object?> json) {
    final ledgerRaw = json['ledger'];
    List<SavingsLedgerEntry> ledger;
    if (ledgerRaw is String) {
      final decoded = jsonDecode(ledgerRaw);
      ledger = decoded is List
          ? [
              for (final item in decoded)
                if (item is Map<String, Object?>)
                  SavingsLedgerEntry.fromJson(item),
            ]
          : const [];
    } else if (ledgerRaw is List) {
      ledger = [
        for (final item in ledgerRaw)
          if (item is Map<String, Object?>) SavingsLedgerEntry.fromJson(item),
      ];
    } else {
      ledger = const [];
    }
    return SavingsPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      goal: (json['goal'] as num?)?.toInt() ?? 0,
      saved: (json['saved'] as num?)?.toInt() ?? 0,
      note: json['note'] as String? ?? '',
      dueAt: json['dueAt'] as int?,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      sortOrder: json['sortOrder'] as int? ?? json['createdAt'] as int? ?? 0,
      deleted: json['deleted'] as bool? ?? false,
      ledger: ledger,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'id': id,
      'name': name,
      'goal': goal,
      'saved': saved,
      'note': note,
      'due_at': dueAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'sort_order': sortOrder,
      'deleted': deleted ? 1 : 0,
      'ledger': jsonEncode([for (final e in ledger) e.toJson()]),
    };
  }

  factory SavingsPlan.fromDb(Map<String, Object?> row) {
    final ledgerRaw = row['ledger'] as String? ?? '[]';
    List<SavingsLedgerEntry> ledger;
    try {
      final decoded = jsonDecode(ledgerRaw);
      ledger = decoded is List
          ? [
              for (final item in decoded)
                if (item is Map<String, Object?>)
                  SavingsLedgerEntry.fromJson(item),
            ]
          : const [];
    } on FormatException {
      ledger = const [];
    }
    return SavingsPlan(
      id: row['id'] as String,
      name: row['name'] as String,
      goal: (row['goal'] as num?)?.toInt() ?? 0,
      saved: (row['saved'] as num?)?.toInt() ?? 0,
      note: row['note'] as String? ?? '',
      dueAt: row['due_at'] as int?,
      createdAt: row['created_at'] as int? ?? 0,
      updatedAt: row['updated_at'] as int? ?? 0,
      sortOrder: row['sort_order'] as int? ?? row['created_at'] as int? ?? 0,
      deleted: (row['deleted'] as int? ?? 0) == 1,
      ledger: ledger,
    );
  }
}

const Object _notSet = Object();
