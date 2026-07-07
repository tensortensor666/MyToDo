import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/app_controller.dart';

void main() {
  test('daily refresh is scheduled just after the next midnight', () {
    final delay = AppController.delayUntilNextDailyRefresh(
      DateTime(2026, 7, 7, 23, 59, 30),
    );

    expect(delay, const Duration(seconds: 31));
  });
}
