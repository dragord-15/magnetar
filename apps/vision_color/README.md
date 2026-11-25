# Vision Color - GUI Object Recognition (Magnetar)

Camera-based color object detection with a graphical interface.  
Detects materials/objects by color, draws a bounding box around them, and reports their size (length/width) in pixels (and optionally cm) - similar to common Python/OpenCV color-tracking demos.

## Features
- Live camera view (V4L2 via `ffmpeg`) in an X11/framebuffer window
- Detection modes: **Motion** (default, frame differencing - tracks moving objects only; stationary ones are ignored), **Red, Green, Blue, Yellow** (HSV blob detection)
- Bounding box + center cross on detected objects (largest highlighted)
- Reports: bbox (x,y,w,h), center, area, **Length(H)/Width(W) in px**, estimated size in cm (with calibration), and robot steering/distance hints
- Pure Magnetar: `lib/gui.mg` + `lib/image.mg` + `lib/vision.mg`

## Requirements
- Linux with a camera device (e.g. `/dev/video0`)
- `ffmpeg` installed (used to capture frames)
- GUI environment: X11 (`DISPLAY`) or DRM/framebuffer

## Build
```bash
./magc vision_color/main.mg -o build/vision_color
```

## Run
```bash
./build/vision_color              # uses /dev/video0
./build/vision_color /dev/video1  # custom device
```

## Controls
- `5` / `M` : Motion (default) - detects only moving objects, ignores stationary ones
- `,` / `.` : decrease/increase motion sensitivity threshold (lower = more sensitive)
- `1` / `R` : Red
- `2` / `G` : Green
- `3` / `B` : Blue
- `4` / `Y` : Yellow
- `+` / `-` : calibrate pixels-per-cm (shows size in cm when set)
- `[` / `]` : decrease/increase minimum detection area
- `Q` / `ESC` : quit

## Notes
- "Length/Width" are the detected bounding-box dimensions in pixels (height/width of the object region). Set `px/cm` (+/-) using a known-size object at the same distance to get an approximate real-world size in cm.
- Works best with distinct, saturated colored objects and consistent lighting. Default capture is 320x240 for responsiveness.
