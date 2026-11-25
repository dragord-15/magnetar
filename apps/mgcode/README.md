# MGCode (Magnetar Code Desktop)

Native desktop code editor for Magnetar, built with `lib/gui.mg` (X11 window / DRM card0 dual-mode).

## Build & Run
From repo root:
```bash
./magc mgcode/main.mg -o build/mgcode
./build/mgcode [path/to/file.mg]
```

## Capabilities (inherited from modular mgedit base)
- Multi-subsystem editor: document/buffer/history/cursor/selection/view
- Syntax highlighting, search, autocomplete
- File tree sidebar and folder open
- Build and bundle/merge workflows, lint panel
- Keyboard shortcuts: `Ctrl+O` open, `Ctrl+Shift+O` open folder, `Ctrl+S` save, `Ctrl+Shift+S` save as, `Ctrl+B` build, `Ctrl+M` bundle, `Ctrl+F` find, `Ctrl+T` tree, `Ctrl+D` theme

## Notes
- GUI requires a graphical environment (X11/desktop) or supported framebuffer/card0 mode.
- File/folder dialogs may require `zenity`.
