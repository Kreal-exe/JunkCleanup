#!/bin/bash
# Builds JunkCleanup for Linux (Avalonia, LinuxApp/) as a self-contained single file: no .NET needed on the target.
#
#   ./build-linux.sh                 dist/JunkCleanup-linux-x64.tar.gz
#   ./build-linux.sh --test          run the Linux core tests first (they also run on macOS)
#   ./build-linux.sh --appimage      also dist/JunkCleanup-x86_64.AppImage (downloads appimagetool once)
#   ./build-linux.sh --arch arm64    build for 64-bit ARM instead
#
# Needs the .NET 10 SDK. The version is the <Version> of src/JunkCleanup/JunkCleanup.csproj, shared by all apps.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$ROOT/src/JunkCleanup/JunkCleanup.csproj" | head -1)"
ARCH=x64
TEST=0
APPIMAGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --test) TEST=1 ;;
    --appimage) APPIMAGE=1 ;;
    --arch) ARCH="$2"; shift ;;
    *) sed -n '2,9p' "$0"; exit 1 ;;
  esac
  shift
done
case "$ARCH" in
  x64) APPIMAGE_ARCH=x86_64 ;;
  arm64) APPIMAGE_ARCH=aarch64 ;;
  *) echo "Unknown architecture: $ARCH (x64 or arm64)" >&2; exit 1 ;;
esac

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
OUT="$(mktemp -d -t junkcleanup-linux.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT

if [ "$TEST" = 1 ]; then
  echo "Running the Linux core tests..."
  dotnet test "$ROOT/tests/JunkCleanup.Linux.Tests" -c Release
fi

echo "Building JunkCleanup $VERSION for linux-$ARCH..."
PKG="$OUT/JunkCleanup"
dotnet publish "$ROOT/LinuxApp/JunkCleanup.Linux.csproj" -c Release -r "linux-$ARCH" --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none -o "$OUT/publish"
mkdir -p "$PKG"
cp "$OUT/publish/JunkCleanup" "$PKG/"
cp "$ROOT/LinuxApp/packaging/junkcleanup.desktop" "$ROOT/LinuxApp/packaging/install.sh" "$PKG/"
cp "$ROOT/LinuxApp/Assets/icon.png" "$PKG/junkcleanup.png"
cp "$ROOT/LICENSE" "$PKG/"
chmod +x "$PKG/JunkCleanup" "$PKG/install.sh"

mkdir -p "$ROOT/dist"
TARBALL="$ROOT/dist/JunkCleanup-linux-$ARCH.tar.gz"
tar -C "$OUT" -czf "$TARBALL" JunkCleanup
echo "Release archive: $TARBALL"

if [ "$APPIMAGE" = 1 ]; then
  TOOL_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/junkcleanup-build"
  TOOL="$TOOL_DIR/appimagetool-$(uname -m).AppImage"
  if [ ! -x "$TOOL" ]; then
    mkdir -p "$TOOL_DIR"
    curl -fsSL -o "$TOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage"
    chmod +x "$TOOL"
  fi
  APPDIR="$OUT/JunkCleanup.AppDir"
  mkdir -p "$APPDIR/usr/bin"
  cp "$PKG/JunkCleanup" "$APPDIR/usr/bin/"
  cp "$PKG/junkcleanup.png" "$APPDIR/junkcleanup.png"
  cp "$PKG/junkcleanup.png" "$APPDIR/.DirIcon"
  cp "$PKG/junkcleanup.desktop" "$APPDIR/junkcleanup.desktop"
  printf '#!/bin/sh\nexec "$(dirname "$(readlink -f "$0")")/usr/bin/JunkCleanup" "$@"\n' > "$APPDIR/AppRun"
  chmod +x "$APPDIR/AppRun"
  IMAGE="$ROOT/dist/JunkCleanup-$APPIMAGE_ARCH.AppImage"
  # appimagetool is an AppImage itself; extracting it avoids needing FUSE on build machines and CI runners.
  ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$APPDIR" "$IMAGE" >/dev/null
  echo "AppImage: $IMAGE"
fi
