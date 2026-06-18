#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$ROOT_DIR/payload"
INSTALL_DIR="${MONIX_INSTALL_DIR:-$HOME/.local/opt/monix}"
BIN_DIR="$HOME/.local/bin"
APPLICATIONS_DIR="$HOME/.local/share/applications"

has_wine() {
  command -v wine >/dev/null 2>&1 || command -v wine64 >/dev/null 2>&1
}

install_wine() {
  if has_wine; then
    return 0
  fi

  echo "Wine is required to run this Windows build of Monix on Linux."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y wine64 wine
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y wine
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed wine
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y wine
  else
    echo "Could not detect a supported package manager."
    echo "Install Wine manually, then run this installer again."
    exit 1
  fi
}

if [ ! -f "$PAYLOAD_DIR/Monix.exe" ]; then
  echo "Missing payload/Monix.exe. Run this script from the Monix-Linux package folder."
  exit 1
fi

install_wine

mkdir -p "$INSTALL_DIR"
cp -a "$PAYLOAD_DIR/." "$INSTALL_DIR/"

mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/monix" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$INSTALL_DIR"
exec wine "$INSTALL_DIR/Monix.exe"
EOF
chmod +x "$BIN_DIR/monix"

mkdir -p "$APPLICATIONS_DIR"
cat > "$APPLICATIONS_DIR/monix.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Monix
Comment=Monix system monitor through Wine
Exec=$BIN_DIR/monix
Icon=$INSTALL_DIR/ico.ico
Terminal=false
Categories=Utility;Monitor;
EOF

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi

echo "Monix installed at: $INSTALL_DIR"
echo "Run it with: monix"
