import 'package:fluent_ui/fluent_ui.dart';

/// MyTodo 应用主题配置
class AppTheme {
  AppTheme._();

  /// 主强调色
  static const Color accentColor = Color(0xFF4B6EAF);
  static const Color _lightTextColor = Color(0xFF1F1F1F);
  static const Color _darkTextColor = Color(0xFFF3F3F3);

  /// 浅色主题
  static FluentThemeData lightTheme() {
    return FluentThemeData(
      brightness: Brightness.light,
      accentColor: accentColor.toAccentColor(),
      typography: _typography(_lightTextColor),
    );
  }

  /// 暗色主题（预留）
  static FluentThemeData darkTheme() {
    return FluentThemeData(
      brightness: Brightness.dark,
      accentColor: accentColor.toAccentColor(),
      typography: _typography(_darkTextColor),
    );
  }

  /// 统一的字体配置
  /// 使用 Microsoft YaHei UI 确保中文清晰渲染
  static Typography _typography(Color textColor) {
    return Typography.raw(
      caption: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        fontFamily: 'Microsoft YaHei UI',
        color: textColor,
      ),
      body: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontFamily: 'Microsoft YaHei UI',
        color: textColor,
      ),
      bodyStrong: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
        color: textColor,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        fontFamily: 'Microsoft YaHei UI',
        color: textColor,
      ),
      subtitle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
        color: textColor,
      ),
      title: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
        color: textColor,
      ),
      titleLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
        color: textColor,
      ),
      display: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei UI',
        color: textColor,
      ),
    );
  }
}
