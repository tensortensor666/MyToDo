import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/search/history_search.dart';

void main() {
  testWidgets('history search filter chips switch visible todo groups', (
    tester,
  ) async {
    const todos = [
      TodoItem(
        id: 'active',
        title: 'Active task',
        completed: false,
        deleted: false,
        createdAt: 1000,
        updatedAt: 1000,
      ),
      TodoItem(
        id: 'completed',
        title: 'Completed task',
        completed: true,
        deleted: false,
        createdAt: 1000,
        updatedAt: 2000,
      ),
      TodoItem(
        id: 'deleted',
        title: 'Deleted task',
        completed: false,
        deleted: true,
        createdAt: 1000,
        updatedAt: 3000,
      ),
    ];
    final listenable = ValueNotifier(0);
    addTearDown(listenable.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoHistorySearchResults(
            listenable: listenable,
            searchTodos: (_) => todos,
            query: '',
            initialFilter: HistoryFilter.all,
            onFilterChanged: (_) {},
            itemBuilder: (context, todo) {
              return ListTile(title: Text(todo.title));
            },
          ),
        ),
      ),
    );

    expect(find.text('Active task'), findsOneWidget);
    expect(find.text('Completed task'), findsOneWidget);
    expect(find.text('Deleted task'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '当前'));
    await tester.pump();

    expect(find.text('Active task'), findsOneWidget);
    expect(find.text('Completed task'), findsNothing);
    expect(find.text('Deleted task'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '已完成'));
    await tester.pump();

    expect(find.text('Active task'), findsNothing);
    expect(find.text('Completed task'), findsOneWidget);
    expect(find.text('Deleted task'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '已删除'));
    await tester.pump();

    expect(find.text('Active task'), findsNothing);
    expect(find.text('Completed task'), findsNothing);
    expect(find.text('Deleted task'), findsOneWidget);
  });
}
