# Changelog

## 1.7.0 - 2026-07-23

- Added an always-on-top Windows task widget with tray and title-bar controls.
- Added an Android home-screen widget for the current task snapshot, including one-tap pinning from Settings.
- Kept widget task ordering consistent across lists and refreshed widget data after local changes.
- Added Android widget regression coverage and Android core library desugaring for the notification dependency.
- New tasks no longer receive an automatic end-of-day due date.

## 1.6.1 - 2026-07-16

- Unified the Windows task status switcher with Android around Current and Completed views.
- Kept overdue tasks inside Current, prioritized them at the top, and added a shared overdue-only shortcut.
- Applied the stronger overdue task styling and responsive status overview to Windows.

## 1.6.0 - 2026-07-14

- Simplified the Android task status switcher to Current and Completed while keeping overdue tasks prioritized inside Current.
- Added overdue count badges, stronger overdue task styling, and a quick overdue-only view.
- Added cancellation of daily recurrence from the task editor while retaining the current task.
- Synced recurrence cancellation across devices so archived templates stop generating future tasks.

## 1.5.1 - 2026-07-13

- Added task deletion to the Android editor with confirmation and one-step undo.
- Fixed the delete undo notification so it dismisses automatically after four seconds.
- Added live count badges to the Android current, overdue, and completed filters.

## 1.5.0 - 2026-07-12

- Added savings plans with deposits, withdrawals, progress tracking, local persistence, and cross-device sync.
- Refreshed the Windows and Android interfaces to match the latest prototypes.
- Reworked Android navigation around a sidebar, compact task filters, and streamlined task cards.
- Consolidated Supabase sync configuration and software updates into the settings surface.
- Added first-run prototype data and expanded model, store, migration, and sync regression coverage.

## 1.4.9 - 2026-07-10

- Updated the taskbar, tray, and app icons from the new design.
- Rebuilt Windows icon files as PNG-compressed entries so the resource compiler accepts them.

## 1.4.5 - 2026-07-07

- Added an inline star button on each todo item to mark or unmark important tasks.
- Added task list reassignment from the task editor.
- Added daily recurring task creation from the add-task dialog.
- Defaulted newly created todos to today's due date.
- Added midnight refresh so My Day updates while the app remains open.

## 1.4.4 - 2026-07-06

- Removed LAN pairing and local network device sync.
- Kept Supabase as the only sync path and made configured remote sync trigger immediately after local changes.

## 1.4.3 - 2026-07-06

- Fixed the Windows sidebar toggle so it switches between expanded and compact navigation modes.

## 1.4.2 - 2026-07-06

- Enabled Android backup rules for the remote sync configuration so Supabase settings can be restored after reinstall when Android backup is available.
- Added a regression test for persisted remote sync URL and publishable key settings.

## 1.4.1 - 2026-07-06

- Fixed task row actions so the delete button and drag handle no longer overlap.

## 1.4.0 - 2026-07-06

- Added drag-and-drop manual task ordering in the main task list.
- Persisted task order locally and through sync events so reordered tasks keep the same order across devices.
- Added migration fallback for existing task data without a stored sort order.

## 1.3.5 - 2026-07-06

- Restored the accepted two-pane task UI with list navigation for desktop.
- Added an adaptive Android layout with a compact header and horizontal list switcher.
- Added system list views for My Day, Important, Planned, Inbox, and custom lists.
- Added important flags, custom lists, recurring daily templates, list colors, and sync support for those entities.
- Updated Windows installer output handling and release packaging for the new artifact layout.

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
