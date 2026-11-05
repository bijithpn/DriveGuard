#!/usr/bin/env bash
# Build the DriveGuard release app and install it (macOS).
# Installs to /Applications if writable, otherwise ~/Applications. No sudo used.
# Missing Flutter / CocoaPods are installed via Homebrew (Homebrew is installed if absent).
# Full Xcode must already be installed (App Store); it can't be scripted.
# Usage: ./scripts/install_macos.sh [--no-launch]
set -euo pipefail

LAUNCH=1
for a in "$@"; do
  case "$a" in
    --no-launch) LAUNCH=0 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Unknown option: $a" >&2; exit 2 ;;
  esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS."
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Xcode command line tools (triggers Apple's installer dialog if missing).
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode command line tools (follow the dialog, then this continues)..."
  xcode-select --install >/dev/null 2>&1 || true
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
fi
command -v xcodebuild >/dev/null || die "Full Xcode is required (App Store), then re-run."
xcodebuild -version >/dev/null 2>&1 || die "Xcode needs setup: open Xcode once and accept the license (or run: sudo xcodebuild -license accept)."

# Homebrew: only used if Flutter or CocoaPods is missing.
load_brew() {
  command -v brew >/dev/null && return 0
  local p
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x $p ]]; then eval "$($p shellenv)"; return 0; fi
  done
  return 1
}
ensure_brew() {
  load_brew && return 0
  log "Installing Homebrew (official installer; may ask for your password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew || die "Homebrew install did not complete."
}

load_brew || true
if ! command -v flutter >/dev/null; then
  ensure_brew
  log "Installing Flutter via Homebrew..."
  brew install --cask flutter
fi
if ! command -v pod >/dev/null; then
  ensure_brew
  log "Installing CocoaPods via Homebrew..."
  brew install cocoapods
fi
command -v flutter >/dev/null || die "Flutter is still not on PATH. Open a new terminal and re-run."
command -v pod >/dev/null || die "CocoaPods is still not on PATH. Open a new terminal and re-run."

log "Fetching dependencies..."
flutter pub get

log "Building release app (this can take several minutes)..."
flutter build macos --release

APP_SRC="$(ls -d build/macos/Build/Products/Release/*.app 2>/dev/null | head -1 || true)"
[[ -n "$APP_SRC" ]] || die "Build finished but no .app was found."
APP_NAME="$(basename "$APP_SRC")"

DEST_DIR="/Applications"
if [[ ! -w "$DEST_DIR" ]]; then
  DEST_DIR="$HOME/Applications"
  mkdir -p "$DEST_DIR"
fi
APP_DEST="$DEST_DIR/$APP_NAME"

if pgrep -x "${APP_NAME%.app}" >/dev/null 2>&1; then
  log "Closing the running copy..."
  osascript -e "tell application \"${APP_NAME%.app}\" to quit" >/dev/null 2>&1 || true
  sleep 2
fi

log "Installing to $APP_DEST ..."
rm -rf "$APP_DEST"
ditto "$APP_SRC" "$APP_DEST"
# Locally built app: remove quarantine flag and ad-hoc sign so it opens without prompts.
xattr -cr "$APP_DEST" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DEST" >/dev/null 2>&1 || true

log "Installed: $APP_DEST"
if [[ $LAUNCH -eq 1 ]]; then open "$APP_DEST"; fi
log "Done."
