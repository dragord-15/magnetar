#!/usr/bin/env bash
set -euo pipefail
# Install MDE on Debian/Ubuntu (target: no existing desktop environment).
# Run as root: sudo bash mde/scripts/install-debian.sh

PREFIX=/usr
LIBDIR=$PREFIX/lib/mde
BINDIR=$PREFIX/bin
CFGDIR=/etc/mde
UNITDIR=/etc/systemd/system
SESSIONDIR=/usr/share/xsessions
WAYLANDDIR=/usr/share/wayland-sessions

echo "[mde] building..."
make -j4
mkdir -p build
./magc mde/compositor/main.mg -o build/mde-compositor
./magc mde/session/main.mg -o build/mde-session
./magc mde/display-manager/main.mg -o build/mde-display-manager
./magc mde/greeter/main.mg -o build/mde-greeter
./magc mde/panel/main.mg -o build/mde-panel
./magc mde/launcher/main.mg -o build/mde-launcher
./magc mde/apps/hello/main.mg -o build/mde-hello
./magc mde/apps/settings/main.mg -o build/mde-settings
./magc mde/apps/files/main.mg -o build/mde-files

echo "[mde] installing..."
install -d "$LIBDIR" "$LIBDIR/apps" "$BINDIR" "$CFGDIR" "$UNITDIR" /usr/share/mde "$SESSIONDIR" "$WAYLANDDIR"
install -m 0755 build/mde-compositor "$LIBDIR/mde-compositor"
install -m 0755 build/mde-session "$LIBDIR/mde-session"
install -m 0755 build/mde-display-manager "$LIBDIR/mde-display-manager"
install -m 0755 build/mde-greeter "$LIBDIR/mde-greeter"
install -m 0755 build/mde-panel "$LIBDIR/mde-panel"
install -m 0755 build/mde-launcher "$LIBDIR/mde-launcher"
install -m 0755 build/mde-hello "$LIBDIR/apps/mde-hello"
install -m 0755 build/mde-settings "$LIBDIR/apps/mde-settings"
install -m 0755 build/mde-files "$LIBDIR/apps/mde-files"
install -m 0644 mde/config/mde.json "$CFGDIR/mde.json"
install -m 0644 mde/scripts/mde-dm.service "$UNITDIR/mde-dm.service"
install -m 0644 mde/scripts/mde.desktop "$WAYLANDDIR/mde.desktop"

cat > "$BINDIR/mde-session" <<'EOF'
#!/usr/bin/env bash
exec /usr/lib/mde/mde-session "$@"
EOF
chmod 0755 "$BINDIR/mde-session"

echo "[mde] installed."
echo "WARNING: mde-dm is MVP; test in dev before replacing production DM."
echo "Enable: sudo systemctl disable gdm3 sddm lightdm gdm || true"
echo "        sudo systemctl enable mde-dm.service"
