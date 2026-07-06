import 'package:fluent_ui/fluent_ui.dart';

/// MyTodo 应用主题配置
class AppTheme {
  AppTheme._();

  /// 主强调色
  static const Color accentColor = Color(0xFF4B6EAF);

  /// 浅色主题
  static FluentThemeData lightTheme() {
    return FluentThemeData(
      brightness: Brightness.light,
      accentColor: accentColor.toAccentColor(),
      typography: _typography(),
    );
  }

  /// 暗色主题（预留）
  static FluentThemeData darkTheme() {
    return FluentThemeData(
      brightness: Brightness.dark,
      accentColor: accentColor.toAccentColor(),
      typography: _typography(),
    );
  }

  /// 统一的字体配置
  /// 使用 Microsoft YaHei UI 确保中文清晰渲染
  static Typography _typography() {
    return Typography.raw(
      caption: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        fontFamily: 'Microsoft YaHei UI',
      ),
      body: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontFamily: 'Microsoft YaHei UI',
      ),
      bodyStrong: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        fontFamily: 'Microsoft YaHei UI',
      ),
      subtitle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
      ),
      title: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
      ),
      titleLarge: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
      ),
      display: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
      ),
    );
  }
}
