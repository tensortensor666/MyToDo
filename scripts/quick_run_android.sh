#!/usr/bin/env bash
# 把改动快速推到雷电模拟器：使用 flutter run 走调试通道，window 同时用 release exe 看效果。
# 默认端口 emulator-5554。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ADB="${ADB_BIN:-C:/leidian/LDPlayer9/adb.exe}"
FLUTTER="${FLUTTER_BIN:-flutter}"

echo "[quick_run] flutter devices"
"$FLUTTER" devices

echo "[quick_run] flutter run -d emulator-5554 --no-hot --start-paused=false"
"$FLUTTER" run -d emulator-5554 --debug
