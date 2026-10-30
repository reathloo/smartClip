#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"

if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi

mode="real"
run_checks=false

case "${1:-}" in
  "") ;;
  --ui) mode="ui" ;;
  --check) run_checks=true ;;
  --help|-h)
    cat <<'EOF'
Usage: zsh scripts/run-dev.sh [--ui|--check]

  no option  Build and restart the real SmartClip app
  --ui       Build and restart an isolated app with synthetic test data
  --check    Run all core checks, then restart the real app
EOF
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Run 'zsh scripts/run-dev.sh --help' for usage." >&2
    exit 2
    ;;
esac

stop_app() {
  local executable="$1"
  local pid
  local -a pids

  find_pids() {
    ps -axo pid=,command= | awk -v target="$executable" '$2 == target { print $1 }'
  }

  pids=("${(@f)$(find_pids)}")
  (( ${#pids} == 0 )) && return 0

  kill -TERM "${pids[@]}" 2>/dev/null || true
  for _ in {1..20}; do
    [[ -n "$(find_pids)" ]] || return 0
    sleep 0.1
  done

  pids=("${(@f)$(find_pids)}")
  (( ${#pids} == 0 )) || kill -KILL "${pids[@]}" 2>/dev/null || true
}

if [[ "$mode" == "ui" ]]; then
  zsh scripts/build-ui-test-app.sh
  app="${PWD}/.build/SmartClip Test.app"
  stop_app "$app/Contents/MacOS/SmartClip"
  open "$app"
  echo "Opened SmartClip Test with synthetic data."
  exit 0
fi

if [[ "$run_checks" == true ]]; then
  zsh scripts/test.sh
else
  swift build
fi

app="${PWD}/dist/SmartClip.app"
stop_app "$app/Contents/MacOS/SmartClip"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/debug/SmartClip "$app/Contents/MacOS/SmartClip"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
zsh scripts/embed-sparkle.sh debug "$app"
codesign --force --deep --sign - "$app"
open "$app"
echo "Opened the current development build at $app"
