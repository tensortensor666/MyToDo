#!/usr/bin/env bash
# 自动编译 Windows exe + Android apk，并安装到雷电模拟器。
# 依赖：flutter 在 PATH；adb 用 LDPlayer 自带的。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FLUTTER="${FLUTTER_BIN:-flutter}"
ADB="${ADB_BIN:-C:/leidian/LDPlayer9/adb.exe}"
APK_OUTPUT="build/app/outputs/flutter-apk/app-debug.apk"
EXE_OUTPUT="build/windows/x64/runner/Release/mytodo.exe"

echo "[build_all] flutter --version"
"$FLUTTER" --version >/dev/null

echo "[build_all] flutter clean (optional, 跳过缓存防爆)"
"$FLUTTER" clean >/dev/null

echo "[build_all] flutter pub get"
"$FLUTTER" pub get

# 1. Windows exe
echo "[build_all] flutter build windows --release"
"$FLUTTER" build windows --release

if [ ! -f "$EXE_OUTPUT" ]; then
  echo "ERROR: $EXE_OUTPUT not produced" >&2
  exit 2
fi
echo "[build_all] exe -> $EXE_OUTPUT"

# 2. Android apk（雷电模拟器运行 x86_64）
echo "[build_all] flutter build apk --debug --target-platform=android-x64"
"$FLUTTER" build apk --debug --target-platform=android-x64

if [ ! -f "$APK_OUTPUT" ]; then
  echo "ERROR: $APK_OUTPUT not produced" >&2
  exit 3
fi
echo "[build_all] apk -> $APK_OUTPUT"

# 3. 雷电模拟器
echo "[build_all] adb devices"
"$ADB" devices

APK_BASENAME="$(basename "$APK_OUTPUT")"
echo "[build_all] push apk to /data/local/tmp/$APK_BASENAME"
"$ADB" push "$APK_OUTPUT" "/data/local/tmp/$APK_BASENAME" >/dev/null

echo "[build_all] pm install on device"
"$ADB" shell pm install -r -t "/data/local/tmp/$APK_BASENAME"

echo "[build_all] DONE"
