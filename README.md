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
