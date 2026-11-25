#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export DISPLAY=${DISPLAY:-:0}
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
echo "[mde] running session (dev mode)"
exec ./build/mde-session --mode=dev --compositor=./build/mde-compositor
