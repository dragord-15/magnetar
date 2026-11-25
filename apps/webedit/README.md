# Magnetar WebEdit

VSCode-like web editor with a Magnetar (`.mg`) HTTP backend and HTML/CSS/JS frontend.

## Features
- File explorer (expand folders, create file/folder, refresh)
- Multi-tab editor with modified indicators
- Line numbers + basic syntax highlighting (Magnetar/JS/C-like)
- Save (`Ctrl+S`), Build current file with `magc` (`Ctrl+B`)
- Quick open (`Ctrl+P`), search panel, bottom output panel
- Backend APIs: `/api/ping,cwd,list,read,save,mkdir,delete,search,build`

## Build & Run
From repo root:
```bash
./magc webedit/server.mg -o build/webedit_server
./build/webedit_server
```
Open http://127.0.0.1:8765

> Note: port 8080 is avoided because it may be used by other services on this machine.

## Desktop app
A native desktop code editor built with `lib/gui.mg` (X11/card0 dual-mode) is scaffolded in `mgcode/`:
```bash
./magc mgcode/main.mg -o build/mgcode
./build/mgcode [file.mg]
```
`mgcode` is based on the modular `mgedit` architecture (file tree, syntax, search, build/bundle, lint) rebranded for Magnetar Code.
