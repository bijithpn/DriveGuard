#!/usr/bin/env bash
# Build the DriveGuard release bundle and install it for the current user (Linux).
# Installs under ~/.local (app, launcher, menu entry).
# Missing build dependencies are installed with apt/dnf/pacman/zypper (sudo, only if needed);
# a missing Flutter SDK is cloned to ~/flutter. The app install itself needs no root.
# Usage: ./scripts/install_linux.sh [--no-launch]
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

[[ "$(uname -s)" == "Linux" ]] || die "This script is for Linux."
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SUDO=""
if [[ $EUID -ne 0 ]]; then SUDO="sudo"; fi

# Is everything needed for a Linux desktop build present?
deps_ok() {
  local t
  for t in git curl unzip clang cmake ninja pkg-config; do
    command -v "$t" >/dev/null || return 1
  done
  pkg-config --exists gtk+-3.0 sqlite3 libnotify \
    && { pkg-config --exists ayatana-appindicator3-0.1 || pkg-config --exists appindicator3-0.1; }
}

# Install only what is missing, using the system package manager.
if ! deps_ok; then
  log "Installing missing build dependencies (needs sudo)..."
  if [[ -n "$SUDO" ]] && ! command -v sudo >/dev/null; then
    die "Build dependencies are missing and sudo is unavailable. See docs/packaging.md."
  fi
  if command -v apt-get >/dev/null; then
    $SUDO apt-get update
    $SUDO apt-get install -y git curl unzip xz-utils zip clang cmake ninja-build pkg-config \
      libgtk-3-dev libayatana-appindicator3-dev libnotify-dev libsqlite3-dev libglu1-mesa
  elif command -v dnf >/dev/null; then
    $SUDO dnf install -y git curl unzip xz zip clang cmake ninja-build pkgconf-pkg-config \
      gtk3-devel libayatana-appindicator-gtk3-devel libnotify-devel sqlite-devel mesa-libGLU
  elif command -v pacman >/dev/null; then
    $SUDO pacman -S --needed --noconfirm git curl unzip xz zip clang cmake ninja pkgconf \
      gtk3 libayatana-appindicator libnotify sqlite glu
  elif command -v zypper >/dev/null; then
    $SUDO zypper --non-interactive install git curl unzip xz zip clang cmake ninja pkg-config \
      gtk3-devel libayatana-appindicator3-devel libnotify-devel sqlite3-devel glu-devel
  else
    die "Unsupported distro: install GTK3, appindicator, libnotify, sqlite, clang, cmake, ninja manually."
  fi
  deps_ok || die "Some build dependencies are still missing after install."
fi

# Flutter SDK: use the existing one, else clone stable into ~/flutter.
if ! command -v flutter >/dev/null; then
  if [[ ! -x "$HOME/flutter/bin/flutter" ]]; then
    log "Flutter not found; downloading the stable SDK to ~/flutter ..."
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
  fi
  export PATH="$HOME/flutter/bin:$PATH"
fi
flutter config --enable-linux-desktop >/dev/null

log "Fetching dependencies..."
flutter pub get

log "Building release bundle (this can take several minutes)..."
flutter build linux --release

BUNDLE="$(ls -d build/linux/*/release/bundle 2>/dev/null | head -1 || true)"
[[ -n "$BUNDLE" && -x "$BUNDLE/driveguard" ]] || die "Build finished but bundle/driveguard was not found."

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
# Keep the bundle away from $DATA_HOME/driveguard: that is the app's own data dir
# (getApplicationSupportDirectory), where it creates a "driveguard/" folder for its
# database. Installing the bundle there collides with the executable and gets wiped.
PREFIX="$DATA_HOME/driveguard-app"
LEGACY="$DATA_HOME/driveguard"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/512x512/apps"
mkdir -p "$BIN_DIR" "$APPS_DIR" "$ICON_DIR"

if pgrep -x driveguard >/dev/null 2>&1; then
  log "Closing the running copy..."
  pkill -x driveguard || true
  sleep 1
fi

# Remove bundle files left by older versions of this script, but keep app data.
if [[ -f "$LEGACY/driveguard" ]]; then
  rm -f "$LEGACY/driveguard"
  rm -rf "$LEGACY/lib"
  [[ -d "$LEGACY/data/flutter_assets" ]] && rm -rf "$LEGACY/data/flutter_assets" "$LEGACY/data/icudtl.dat"
  rmdir "$LEGACY/data" 2>/dev/null || true
fi

log "Installing to $PREFIX ..."
rm -rf "$PREFIX"
mkdir -p "$PREFIX"
cp -a "$BUNDLE"/. "$PREFIX"/
ln -sf "$PREFIX/driveguard" "$BIN_DIR/driveguard"
if [[ -f linux/driveguard.png ]]; then cp linux/driveguard.png "$ICON_DIR/driveguard.png"; fi

cat > "$APPS_DIR/driveguard.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=DriveGuard
Comment=SSD/HDD temperature and health monitor
Exec=$PREFIX/driveguard
Icon=driveguard
Terminal=false
Categories=System;Monitor;
DESKTOP
update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true

# Disk access: reading SMART/NVMe health needs more than the "disk" group - the kernel
# requires CAP_SYS_ADMIN (NVMe admin commands) and CAP_SYS_RAWIO (USB bridges) for
# smartctl. Grant exactly those two capabilities to smartctl only (one-time, needs sudo;
# the app itself never runs as root), and re-apply them after smartmontools upgrades.
if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null; then
  log "sudo unavailable; skipping disk-access setup (see docs/permissions.md)."
elif command -v smartctl >/dev/null && command -v setcap >/dev/null; then
  SMARTCTL_REAL="$(readlink -f "$(command -v smartctl)")"
  CAPS="cap_sys_admin,cap_sys_rawio+ep"
  if ! getcap "$SMARTCTL_REAL" 2>/dev/null | grep -q cap_sys_rawio; then
    log "Granting smartctl disk access ($CAPS) (needs sudo)..."
    $SUDO setcap "$CAPS" "$SMARTCTL_REAL" \
      || log "Could not set capabilities; run: sudo setcap $CAPS $SMARTCTL_REAL"
  fi
  if command -v apt-get >/dev/null && [[ ! -f /etc/apt/apt.conf.d/99-driveguard-smartctl ]]; then
    printf 'DPkg::Post-Invoke { "f=$(readlink -f /usr/sbin/smartctl); [ -x \"$f\" ] && /usr/sbin/setcap %s \"$f\" 2>/dev/null || true"; };\n' "$CAPS" \
      | $SUDO tee /etc/apt/apt.conf.d/99-driveguard-smartctl >/dev/null || true
  fi
else
  log "smartctl/setcap not found; disk health may show 'permission required' (see docs/permissions.md)."
fi

log "Installed: $PREFIX"
if [[ $LAUNCH -eq 1 && -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  nohup "$PREFIX/driveguard" >/dev/null 2>&1 &
fi
log "Done."
