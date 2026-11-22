#!/usr/bin/env bash
# Build Awning.app.
#   ./build.sh            build into build/Awning.app
#   ./build.sh run        build, then (re)launch
#   ./build.sh install    build, then copy to /Applications and launch
#   ./build.sh test       run the unit tests
#   UNIVERSAL=1 ./build.sh   arm64 + x86_64 binary
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ "${1:-}" == "test" ]]; then
    exec swift test
fi

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Compiling (release)…"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/Awning.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Awning" "$APP/Contents/MacOS/Awning"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature over the whole bundle (needed for Launch at Login to recognise it).
codesign --force --sign - "$APP" >/dev/null

launch() {
    pkill -x Awning 2>/dev/null || true
    sleep 0.2
    open "$1"
}

case "${1:-}" in
    run)
        launch "$APP"
        ;;
    install)
        echo "==> Installing to /Applications"
        pkill -x Awning 2>/dev/null || true
        rm -rf /Applications/Awning.app
        cp -R "$APP" /Applications/
        launch /Applications/Awning.app
        ;;
esac
echo "==> Done: $APP"
