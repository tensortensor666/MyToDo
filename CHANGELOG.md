# Changelog

## 1.3.4 - 2026-06-27

- Added clickable current, overdue, and completed filters on the main task view.
- Reduced main-screen clutter by hiding overdue and completed tasks unless their filter is selected.
- Added a desktop-friendly immediate sync button in the top app bar with an in-progress state.

## 1.3.3 - 2026-06-27

- Added pull-to-refresh sync on the main task list.
- Kept pull-to-refresh available even when the task list is empty.

## 1.3.2 - 2026-06-27

- Changed Android release builds to require a stable release keystore from GitHub Secrets.
- Added Android release signing documentation and a local keystore generation script.
- Prevented CI from publishing APKs with unstable debug signatures.

## 1.3.1 - 2026-06-27

- Removed bundled Supabase project URL and publishable key from the release build.
- Added optional automatic Supabase remote sync after local changes and periodic background sync.

## 1.3.0 - 2026-06-27

- Added configurable Supabase remote sync using the REST API and publishable keys.
- Added a Supabase remote sync panel under sync/devices with connection testing and manual sync.
- Reworked history search filtering into a testable component so filter chips update immediately.

## 1.2.0 - 2026-06-27

- Added an in-app update checker for Android and Windows.
- Added official GitHub downloads plus selectable domestic accelerated mirrors.
- Defaulted Chinese-region clients to an accelerated download source while keeping SHA256 checksum access.

## 1.1.1 - 2026-06-27

- Fixed Android QR pairing crash in release builds by disabling R8 minification for Android dependencies.
- Added a Chinese scanner error fallback with retry and manual pairing actions.

## 1.1.0 - 2026-06-26

- Added Windows system tray support with show, hide, sync, and quit actions.
- Added close-to-tray behavior for the Windows app.
- Added Windows installer packaging to the GitHub Release workflow.

## 1.0.2 - 2026-06-26

- Added GitHub Actions automation for publishing APK and Windows release assets.
- Included Gradle wrapper files so Android builds work in CI.

## 1.0.1 - 2026-06-26

- Replaced the default launcher icon with a branded MyTodo icon for Android and Windows.

## 1.0.0 - 2026-06-26

- Initial local-first TODO prototype for Android and Windows.
- Added LAN pairing and sync between trusted devices.
- Added created dates, due dates, reminders, history search, backup export, and restore support.
- Refined the main task UI, history search, and sync/device screens.
- Published split-ABI Android release APKs to reduce download size.
