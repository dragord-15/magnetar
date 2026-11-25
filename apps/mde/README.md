# MDE - Magnetar Desktop Environment

Desktop environment written in Magnetar for Debian-family Linux systems (Ubuntu/Debian), targeting machines **without an existing desktop environment**.

## Components

| Component | Path | Status |
|---|---|---|
| Compositor/Shell | `mde/compositor/main.mg` | MVP: X11 dev window + IPC server |
| Session | `mde/session/main.mg` | MVP: spawns compositor + optional panel |
| Display Manager | `mde/display-manager/main.mg` | MVP: greeter then session |
| Greeter | `mde/greeter/main.mg` | MVP: login UI, no PAM yet |
| Panel | `mde/panel/main.mg` | MVP: standalone panel window + IPC hello |
| Launcher | `mde/launcher/main.mg` | MVP: launches apps |
| Files app | `mde/apps/files/main.mg` | MVP: directory list |
| Settings app | `mde/apps/settings/main.mg` | MVP: theme/user/platform |
| IPC Hello app | `mde/apps/hello/main.mg` | IPC test client |
| IPC lib | `lib/ipc.mg` | Unix socket server/client, line JSON |
| MDE IPC protocol | `lib/mde_ipc.mg`, `mde/protocol/mde-ipc-v1.md` | v1 MVP |

## Build

```bash
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
```

## Dev run (Ubuntu/X11 existing desktop)

```bash
bash mde/scripts/dev-run.sh
# or
DISPLAY=:0 ./build/mde-session --mode=dev --compositor=./build/mde-compositor
```

## IPC test

```bash
# terminal 1
DISPLAY=:0 ./build/mde-compositor
# terminal 2
./build/mde-hello
```

## Debian/Ubuntu install (target: no DE)

```bash
sudo bash mde/scripts/install-debian.sh
sudo systemctl disable gdm3 sddm lightdm gdm || true
sudo systemctl enable mde-dm.service
sudo reboot
```

> **Warning**: `mde-dm` is MVP. It does not yet implement full PAM/logind/seat management. Test in dev mode or a VM before replacing a production display manager.

## Target architecture

- **Dev mode**: X11 window backend from `lib/gui.mg` on existing Debian/Ubuntu desktop.
- **Target mode**: DRM/KMS + evdev compositor on Debian-family system with no DE, launched by `mde-dm.service`.
- **IPC**: Unix domain sockets, JSON line protocol (`mde-ipc-v1`).
- **Apps**: Magnetar native GUI apps; future external app support via Wayland compatibility layer.

## Known limitations / next work

- `process_exec` in backend is stub; session uses `sys_fork/execve/wait4`.
- Static global `int` init `= -1` is buggy in compiler; initialize at runtime.
- `gui_draw_text` takes 6 args; use `gui_draw_text_fg` for 5-arg text.
- X11 event recv can block; `MSG_DONTWAIT` used.
- Greeter has no PAM auth yet.
- No real DRM/KMS+evdev production compositor loop yet (lib/gui has DRM primitives; needs dedicated mde-compositor backend mode).
- No Wayland/X11 client compatibility.
