# MyTodo

[English](README.md)

MyTodo 是一个支持 Windows 和 Android 的本地优先 TODO 应用。数据默认保存在本机，可以在同一局域网内与可信设备同步，也可以配置你自己的 Supabase 项目进行远程同步。

## 运行截图

| Windows | Android |
| --- | --- |
| ![MyTodo Windows 端运行截图](docs/screenshots/windows-home.png) | ![MyTodo Android 端运行截图](docs/screenshots/android-home.png) |

## 功能

- 添加、编辑、完成、删除和恢复 TODO。
- 显示创建时间、截止时间、提醒时间和逾期状态。
- 主界面支持按“当前 / 逾期 / 完成”筛选任务。
- 从顶部栏搜索当前、已完成和已删除的历史任务。
- 支持二维码配对和手动配对，在局域网内同步可信设备。
- 支持配置自己的 Supabase 项目进行远程同步。
- 手机端支持下拉刷新，桌面端提供顶部栏“立即同步”按钮。
- Windows 端支持系统托盘和安装程序。
- 支持应用内检查更新，提供 GitHub 下载和国内镜像加速选项。
- 支持导出 JSON 备份。

## 下载

最新版 APK、Windows 安装程序和 Windows 压缩包可以在这里下载：

https://github.com/tensortensor666/MyToDo/releases/latest

大多数 Android 手机使用 `arm64-v8a` APK。Windows 普通用户建议使用安装程序；如果想免安装运行，可以下载 Windows zip。

## 本地构建

```powershell
flutter pub get
flutter test
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols/android
flutter build windows --release
```

## 发布 Release

推送版本 tag 后，GitHub Actions 会自动构建并发布 Release：

```powershell
git tag -a v1.3.4 -m "MyTodo 1.3.4"
git push origin main
git push origin v1.3.4
```

Release workflow 会上传分 ABI 的 Android APK、Windows x64 zip、Windows 安装程序和 SHA256 校验文件。
