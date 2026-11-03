#!/bin/bash
# Builds JunkCleanup for Linux (Avalonia, LinuxApp/) as one self-contained AppImage: no .NET needed on the target.
#
#   ./build-linux.sh                 dist/JunkCleanup-Linux-v<version>.AppImage (downloads appimagetool once)
#   ./build-linux.sh --test          run the Linux core tests first (they also run on macOS)
#   ./build-linux.sh --arch arm64    build for 64-bit ARM instead (dist/JunkCleanup-Linux-arm64-v<version>.AppImage)
#
# Needs the .NET 10 SDK. The version is the <Version> of src/JunkCleanup/JunkCleanup.csproj, shared by all apps.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$ROOT/src/JunkCleanup/JunkCleanup.csproj" | head -1)"
ARCH=x64
TEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --test) TEST=1 ;;
    --arch) ARCH="$2"; shift ;;
    *) sed -n '2,8p' "$0"; exit 1 ;;
  esac
  shift
done
case "$ARCH" in
  x64) APPIMAGE_ARCH=x86_64; SUFFIX="" ;;
  arm64) APPIMAGE_ARCH=aarch64; SUFFIX="-arm64" ;;
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
dotnet publish "$ROOT/LinuxApp/JunkCleanup.Linux.csproj" -c Release -r "linux-$ARCH" --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none -o "$OUT/publish"

TOOL_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/junkcleanup-build"
TOOL="$TOOL_DIR/appimagetool-$(uname -m).AppImage"
if [ ! -x "$TOOL" ]; then
  mkdir -p "$TOOL_DIR"
  curl -fsSL -o "$TOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage"
  chmod +x "$TOOL"
fi
APPDIR="$OUT/JunkCleanup.AppDir"
mkdir -p "$APPDIR/usr/bin"
cp "$OUT/publish/JunkCleanup" "$APPDIR/usr/bin/"
chmod +x "$APPDIR/usr/bin/JunkCleanup"
cp "$ROOT/LinuxApp/Assets/icon.png" "$APPDIR/junkcleanup.png"
cp "$ROOT/LinuxApp/Assets/icon.png" "$APPDIR/.DirIcon"
cp "$ROOT/LinuxApp/packaging/junkcleanup.desktop" "$APPDIR/junkcleanup.desktop"
printf '#!/bin/sh\nexec "$(dirname "$(readlink -f "$0")")/usr/bin/JunkCleanup" "$@"\n' > "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
mkdir -p "$ROOT/dist"
IMAGE="$ROOT/dist/JunkCleanup-Linux$SUFFIX-v$VERSION.AppImage"
# appimagetool is an AppImage itself; extracting it avoids needing FUSE on build machines and CI runners.
ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$APPDIR" "$IMAGE" >/dev/null
echo "AppImage: $IMAGE"
