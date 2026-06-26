# MyTodo

MyTodo is a local-first Flutter TODO app for Windows and Android. It stores data on the device and syncs trusted devices over the same LAN without a central server.

## Features

- Create, edit, complete, delete, and restore TODO items.
- Store created time, due time, and reminder time.
- Search current, completed, and deleted task history from the app bar.
- Pair devices with QR/manual pairing and sync over LAN.
- Export a JSON backup.

## Build

```powershell
flutter pub get
flutter test
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols/android
flutter build windows --release
```

For Android phones, use the `app-arm64-v8a-release.apk` artifact unless the device specifically needs another ABI.

## Release

Push a version tag to build and publish a GitHub Release automatically:

```powershell
git tag -a v1.0.1 -m "MyTodo 1.0.1"
git push origin main --tags
```

The release workflow uploads split Android APKs, a Windows x64 zip, and a Windows installer. The zip contains `mytodo.exe` plus the Flutter runtime files required to run it.
The Windows installer is built with Inno Setup from `installer/windows/MyTodo.iss`.
