import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/ui/reorder_items.dart';

void main() {
  test(
    'reorderItems uses adjusted ReorderableListView.onReorderItem indexes',
    () {
      expect(reorderItems(['Alpha', 'Bravo', 'Charlie'], 2, 0), [
        'Charlie',
        'Alpha',
        'Bravo',
      ]);

      expect(reorderItems(['Alpha', 'Bravo', 'Charlie'], 0, 2), [
        'Bravo',
        'Charlie',
        'Alpha',
      ]);
    },
  );
}
