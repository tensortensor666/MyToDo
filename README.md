# MyTodo

[中文说明](README.zh-CN.md)

MyTodo is a local-first Flutter TODO app for Windows and Android. It stores data on the device and can optionally sync through your own Supabase project.

## Screenshots

| Windows | Android |
| --- | --- |
| ![MyTodo running on Windows](docs/screenshots/windows-home.png) | ![MyTodo running on Android](docs/screenshots/android-home.png) |

## Features

- Create, edit, complete, delete, and restore TODO items.
- Track created time, due time, reminder time, and overdue state.
- Filter the main list by current, overdue, and completed tasks.
- Search current, completed, and deleted task history from the app bar.
- Optional Supabase remote sync with user-provided project URL and publishable key.
- Automatic remote sync after local changes when Supabase sync is configured.
- Pull-to-refresh on mobile and a top-bar remote sync button for desktop.
- Windows system tray support and Windows installer packaging.
- In-app update checking with GitHub downloads and domestic mirror options.
- Export a JSON backup.

## Download

Download the latest APK, Windows installer, or Windows zip from:

https://github.com/tensortensor666/MyToDo/releases/latest

For most Android phones, use the `arm64-v8a` APK. Use the Windows installer for normal desktop installation, or the Windows zip for portable use.

## Build

```powershell
flutter pub get
flutter test
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols/android
flutter build windows --release
```

## Release

Push a version tag to build and publish a GitHub Release automatically:

```powershell
git tag -a v1.3.4 -m "MyTodo 1.3.4"
git push origin main
git push origin v1.3.4
```

The release workflow uploads split Android APKs, a Windows x64 zip, a Windows installer, and SHA256 checksums.
