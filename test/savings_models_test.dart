import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/savings_models.dart';

void main() {
  group('SavingsPlan four-way serialization round trip', () {
    test('toDb -> fromDb preserves core fields and ledger', () {
      final plan = SavingsPlan(
        id: 'p1',
        name: '换新电脑',
        goal: 20000,
        saved: 6500,
        note: '每月攒一点',
        dueAt: 1800000000000,
        createdAt: 1700000000,
        updatedAt: 1700000500,
        sortOrder: 3,
        ledger: const [
          SavingsLedgerEntry(dateMs: 1700000500, amount: 1500, note: '首笔'),
          SavingsLedgerEntry(dateMs: 1700000600, amount: 5000, note: '奖金'),
          SavingsLedgerEntry(dateMs: 1700000700, amount: -200, note: '应急取出'),
        ],
      );
      final db = plan.toDb();
      expect(db['id'], 'p1');
      expect(db['goal'], 20000);
      expect(db['saved'], 6500);
      expect(db['deleted'], 0);
      expect(db['ledger'], isA<String>());

      final restored = SavingsPlan.fromDb(db);
      expect(restored.id, plan.id);
      expect(restored.name, plan.name);
      expect(restored.goal, plan.goal);
      expect(restored.saved, plan.saved);
      expect(restored.note, plan.note);
      expect(restored.dueAt, plan.dueAt);
      expect(restored.createdAt, plan.createdAt);
      expect(restored.updatedAt, plan.updatedAt);
      expect(restored.sortOrder, plan.sortOrder);
      expect(restored.deleted, isFalse);
      expect(restored.ledger.length, 3);
      expect(restored.ledger[0].amount, 1500);
      expect(restored.ledger[1].note, '奖金');
      expect(restored.ledger[2].amount, -200);
    });

    test('toJson -> fromJson round trip preserves ledger list', () {
      final plan = SavingsPlan(
        id: 'p2',
        name: '旅行',
        goal: 8000,
        saved: 3000,
        note: '',
        createdAt: 1,
        updatedAt: 2,
        sortOrder: 5,
        ledger: const [SavingsLedgerEntry(dateMs: 9, amount: 3000, note: '初始')],
      );
      final json = plan.toJson();
      final restored = SavingsPlan.fromJson(Map<String, Object?>.from(json));
      expect(restored.id, 'p2');
      expect(restored.goal, 8000);
      expect(restored.ledger.single.amount, 3000);
    });

    test('fromJson tolerates ledger as JSON string', () {
      final plan = SavingsPlan(
        id: 'p3',
        name: '应急',
        goal: 5000,
        saved: 1000,
        note: '',
        createdAt: 1,
        updatedAt: 2,
        sortOrder: 0,
        ledger: const [SavingsLedgerEntry(dateMs: 7, amount: 1000, note: 'x')],
      );
      // Serialize ledger to string the way remote payload might carry it.
      final json = plan.toJson();
      json['ledger'] = '[{"dateMs":7,"amount":1000,"note":"x"}]';
      final restored = SavingsPlan.fromJson(json);
      expect(restored.ledger, hasLength(1));
      expect(restored.ledger.single.note, 'x');
    });

    test('fromJson handles missing ledger gracefully', () {
      final restored = SavingsPlan.fromJson(const {
        'id': 'p4',
        'name': '空',
        'goal': 1000,
        'saved': 0,
        'createdAt': 1,
        'updatedAt': 1,
        'sortOrder': 0,
      });
      expect(restored.ledger, isEmpty);
    });
  });

  group('SavingsPlan derived state', () {
    test('isDone only when goal > 0 and saved >= goal', () {
      final done = SavingsPlan(
        id: 'a',
        name: 'n',
        goal: 1000,
        saved: 1000,
        createdAt: 1,
        updatedAt: 1,
        sortOrder: 0,
        ledger: const [],
      );
      final overflow = SavingsPlan(
        id: 'b',
        name: 'n',
        goal: 1000,
        saved: 1200,
        createdAt: 1,
        updatedAt: 1,
        sortOrder: 0,
        ledger: const [],
      );
      final noGoal = SavingsPlan(
        id: 'c',
        name: 'n',
        goal: 0,
        saved: 100,
        createdAt: 1,
        updatedAt: 1,
        sortOrder: 0,
        ledger: const [],
      );
      final partial = SavingsPlan(
        id: 'd',
        name: 'n',
        goal: 1000,
        saved: 999,
        createdAt: 1,
        updatedAt: 1,
        sortOrder: 0,
        ledger: const [],
      );
      expect(done.isDone, isTrue);
      expect(overflow.isDone, isTrue);
      expect(noGoal.isDone, isFalse);
      expect(partial.isDone, isFalse);
    });

    test('remaining never negative and zero when no goal', () {
      expect(
        (SavingsPlan(
          id: 'a',
          name: 'n',
          goal: 1000,
          saved: 1300,
          createdAt: 1,
          updatedAt: 1,
          sortOrder: 0,
          ledger: const [],
        )).remaining,
        0,
      );
      expect(
        (SavingsPlan(
          id: 'b',
          name: 'n',
          goal: 1000,
          saved: 400,
          createdAt: 1,
          updatedAt: 1,
          sortOrder: 0,
          ledger: const [],
        )).remaining,
        600,
      );
      expect(
        (SavingsPlan(
          id: 'c',
          name: 'n',
          goal: 0,
          saved: 100,
          createdAt: 1,
          updatedAt: 1,
          sortOrder: 0,
          ledger: const [],
        )).remaining,
        0,
      );
    });

    test('percent clamps 0..100 and zero when no goal', () {
      expect(
        (SavingsPlan(
          id: 'a',
          name: 'n',
          goal: 1000,
          saved: 1300,
          createdAt: 1,
          updatedAt: 1,
          sortOrder: 0,
          ledger: const [],
        )).percent,
        100,
      );
      expect(
        (SavingsPlan(
          id: 'b',
          name: 'n',
          goal: 1000,
          saved: 250,
          createdAt: 1,
          updatedAt: 1,
          sortOrder: 0,
          ledger: const [],
        )).percent,
        25,
      );
      expect(
        (SavingsPlan(
          id: 'c',
          name: 'n',
          goal: 0,
          saved: 100,
          createdAt: 1,
          updatedAt: 1,
          sortOrder: 0,
          ledger: const [],
        )).percent,
        0,
      );
    });
  });

  group('copyWith sentinel behavior', () {
    test('dueAt can be set to null explicitly', () {
      final plan = SavingsPlan(
        id: 'p',
        name: 'n',
        goal: 1000,
        saved: 0,
        dueAt: 999,
        createdAt: 1,
        updatedAt: 1,
        sortOrder: 0,
        ledger: const [],
      );
      expect(plan.dueAt, 999);
      final cleared = plan.copyWith(dueAt: null);
      expect(cleared.dueAt, isNull);
      final unchanged = plan.copyWith();
      expect(unchanged.dueAt, 999);
    });

    test('createdAt is preserved across copyWith', () {
      final plan = SavingsPlan(
        id: 'p',
        name: 'n',
        goal: 1000,
        saved: 0,
        createdAt: 4242,
        updatedAt: 1,
        sortOrder: 0,
        ledger: const [],
      );
      final next = plan.copyWith(saved: 100);
      expect(next.createdAt, 4242);
      expect(next.saved, 100);
    });
  });
}
