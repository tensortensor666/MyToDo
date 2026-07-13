import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/ui/todo_editor_delete_section.dart';

void main() {
  testWidgets('task editor delete section confirms the current title', (
    tester,
  ) async {
    final titleController = TextEditingController(text: '原任务');
    addTearDown(titleController.dispose);
    String? deletedTitle;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFC96442),
            error: const Color(0xFFB53333),
          ),
        ),
        home: Scaffold(
          body: TodoEditorDeleteSection(
            titleController: titleController,
            fallbackTitle: '原任务',
            onConfirmed: (title) async => deletedTitle = title,
          ),
        ),
      ),
    );

    expect(find.text('危险操作'), findsOneWidget);
    expect(find.text('删除后会返回任务列表，并提供一次撤销机会。'), findsOneWidget);

    final deleteButton = find.byKey(const ValueKey('delete-todo-from-editor'));
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('删除这条任务？'), findsOneWidget);
    expect(find.text('“原任务”将从当前清单移除。'), findsOneWidget);
    await tester.tap(find.text('保留任务'));
    await tester.pumpAndSettle();
    expect(deletedTitle, isNull);

    titleController.text = '编辑后任务';
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(find.text('“编辑后任务”将从当前清单移除。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-delete-todo')));
    await tester.pumpAndSettle();
    expect(deletedTitle, '编辑后任务');
  });

  testWidgets('blank title falls back to the saved task title', (tester) async {
    final titleController = TextEditingController(text: '   ');
    addTearDown(titleController.dispose);
    String? deletedTitle;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoEditorDeleteSection(
            titleController: titleController,
            fallbackTitle: '已保存任务',
            onConfirmed: (title) async => deletedTitle = title,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('delete-todo-from-editor')));
    await tester.pumpAndSettle();
    expect(find.text('“已保存任务”将从当前清单移除。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-delete-todo')));
    await tester.pumpAndSettle();
    expect(deletedTitle, '已保存任务');
  });

  testWidgets('delete undo snackbar dismisses automatically', (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    messengerKey.currentState!.showSnackBar(
      buildTodoDeleteUndoSnackBar(title: '待删除任务', onUndo: () {}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已删除“待删除任务”'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.pump(todoDeleteUndoDuration);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已删除“待删除任务”'), findsNothing);
    expect(find.text('撤销'), findsNothing);
  });
}
