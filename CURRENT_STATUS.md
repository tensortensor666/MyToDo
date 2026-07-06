# Current Status

## Version

- Current release: `1.3.5+12`
- Status: ready for Windows and Android release

## UI

- Desktop uses the accepted two-pane MyTodo layout:
  - Left list navigation
  - Right task content page
  - Current, overdue, and completed filters
- Android uses an adaptive compact layout:
  - Top command bar
  - Horizontal list switcher
  - Single-column task content

## Release Outputs

- Windows installer: `dist/windows/installers/MyTodo-1.3.5-windows-x64-setup.exe`
- Android APKs: `dist/android/apk/`
- Checksums: `dist/checksums/SHA256SUMS-1.3.5.txt`

## Verification

- `flutter analyze`
- `flutter test`
- `flutter build windows --release`
- `flutter build apk --release --split-per-abi`
