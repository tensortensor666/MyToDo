import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/update/app_update_service.dart';

void main() {
  test('compares release versions without tag prefixes or build metadata', () {
    expect(AppUpdateService.compareVersions('v1.2.0', '1.1.9'), greaterThan(0));
    expect(AppUpdateService.compareVersions('1.2.0+6', '1.2.0+5'), 0);
    expect(AppUpdateService.compareVersions('1.10.0', '1.2.9'), greaterThan(0));
    expect(AppUpdateService.compareVersions('1.0.0', '1.0.1'), lessThan(0));
  });

  test('prefers domestic mirror for Chinese locale users', () {
    final mirror = AppUpdateService.recommendedDownloadMirror(
      languageCode: 'zh',
      countryCode: 'CN',
    );

    expect(mirror.isOfficial, isFalse);
    expect(mirror.label, contains('国内加速'));
  });

  test('uses official download source outside Chinese locales', () {
    final mirror = AppUpdateService.recommendedDownloadMirror(
      languageCode: 'en',
      countryCode: 'US',
    );

    expect(mirror.isOfficial, isTrue);
  });
}
