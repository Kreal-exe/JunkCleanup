#!/bin/sh
# Installs JunkCleanup for the current user: the app into ~/.local/bin, its icon and its menu entry.
#   ./install.sh              install (or update)
#   ./install.sh --uninstall  remove it again (your settings in ~/.config/JunkCleanup are kept)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$BIN/JunkCleanup" "$APPS/junkcleanup.desktop" "$ICONS/junkcleanup.png"
  echo "JunkCleanup removed."
  exit 0
fi

mkdir -p "$BIN" "$APPS" "$ICONS"
install -m 755 "$HERE/JunkCleanup" "$BIN/JunkCleanup"
install -m 644 "$HERE/junkcleanup.png" "$ICONS/junkcleanup.png"
sed "s|^Exec=.*|Exec=$BIN/JunkCleanup|" "$HERE/junkcleanup.desktop" > "$APPS/junkcleanup.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" >/dev/null 2>&1 || true
echo "Installed: $BIN/JunkCleanup (find it in the app menu as JunkCleanup)."
