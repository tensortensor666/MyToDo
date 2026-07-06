# MyTodo

[English](README.md) | [产品规划](docs/PRODUCT_ROADMAP.md) | [开发文档](docs/)

MyTodo 是一个支持 Windows 和 Android 的本地优先 TODO 应用。数据默认保存在本机，也可以配置你自己的 Supabase 项目进行远程同步。

## 运行截图

| Windows | Android |
| --- | --- |
| ![MyTodo Windows 端运行截图](docs/screenshots/windows-home.png) | ![MyTodo Android 端运行截图](docs/screenshots/android-home.png) |

## ✨ 功能特性

### 任务管理
- ✅ 添加、编辑、完成、删除和恢复 TODO
- ✅ 截止时间、提醒时间和逾期状态
- ✅ 重要任务标记
- ✅ 自定义清单和颜色
- ✅ 日常任务模板（每日自动生成）

### 视图和筛选
- ✅ 我的一天 - 今日待办
- ✅ 重要 - 标星任务
- ✅ 已计划 - 有截止日期的任务
- ✅ 自定义清单分类
- ✅ 历史搜索（包含已删除任务）

### 同步功能
- ✅ Supabase 远程同步（可选）
- ✅ 本地任务变化后自动触发远程同步
- ✅ 下拉刷新远程同步
- ✅ 导出 JSON 备份

### 桌面特性
- ✅ Windows 系统托盘
- ✅ Fluent UI 设计风格
- ✅ 应用内更新检查
- ✅ 键盘快捷键支持

## 🚀 即将推出

### v1.4.0 - UI 优化（计划中）
- 🎨 暗色模式
- 🎨 自定义主题色
- ✨ 任务完成动画
- 📊 任务统计图表
- 🔍 高级搜索筛选

查看完整的 [产品规划](docs/PRODUCT_ROADMAP.md)

## 📥 下载

最新版 APK、Windows 安装程序和 Windows 压缩包可以在这里下载：

https://github.com/tensortensor666/MyToDo/releases/latest

大多数 Android 手机使用 `arm64-v8a` APK。Windows 普通用户建议使用安装程序；如果想免安装运行，可以下载 Windows zip。

## 🛠️ 本地构建

### 前置要求
- Flutter 3.12.2 或更高版本
- Dart 3.12.2 或更高版本

### 构建命令
```powershell
# 安装依赖
flutter pub get

# 运行测试
flutter test

# 构建 Android APK
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols/android

# 构建 Windows
flutter build windows --release
```

## 📚 开发文档

- [项目清理总结](docs/PROJECT_CLEANUP_SUMMARY.md)
- [重构计划](docs/REFACTORING_PLAN.md)
- [UI 改善指南](docs/UI_IMPROVEMENT_GUIDE.md)
- [产品规划](docs/PRODUCT_ROADMAP.md)
- [Bug 报告](BUG_REPORT.md)
- [字体优化指南](FONT_FIX_GUIDE.md)

## 🔧 技术栈

- **框架**: Flutter 3.44+
- **UI 库**: Fluent UI 4.16
- **数据库**: SQLite (sqflite)
- **同步**: HTTP + Supabase
- **平台**: Windows, Android, iOS, Web

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

### 开发流程
1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'feat: add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

### 代码规范
- 遵循 Flutter/Dart 官方风格指南
- 运行 `flutter analyze` 确保无警告
- 所有测试必须通过 (`flutter test`)
- 为新功能添加测试用例

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 📮 联系方式

- Issues: https://github.com/tensortensor666/MyToDo/issues
- Discussions: https://github.com/tensortensor666/MyToDo/discussions

## 🌟 致谢

感谢所有贡献者和用户的支持！
