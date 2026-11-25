# lib/game2d.mg

2D game primitives built on `lib/gui.mg`.

## Features
- Window/frame: `g2d_init_window`, `g2d_running`, `g2d_begin`, `g2d_clear`, `g2d_end/present`, `g2d_shutdown`
- Drawing: pixel/rect/line/circle/triangle, `g2d_text`
- Math/types: `Vec2i`, `Rect2D`, clamp/lerp/overlap helpers
- Camera: `Camera2D`, `camera2d_world_to_screen`, `camera2d_follow`
- Sprites/entities: `Sprite2D`, move/anim/draw/collision helpers, `ImageSprite2D`
- Tilemap: `Tilemap2D` set/get/draw/collision
- Animation/input/timer: `Animation2D`, `Input2D`, `Timer2D`

## Example
```mg
use "lib/gui.mg";
use "lib/game2d.mg";

fn main() -> int {
    g2d_init_window(800, 600, "Game2D");
    Camera2D cam = camera2d_new(800, 600);
    Sprite2D p = sprite2d_new(100, 100, 32, 32, gui_rgb(80,200,120));
    while (g2d_running()) {
        g2d_begin();
        g2d_clear(gui_rgb(20,24,32));
        sprite2d_draw(&p, &cam);
        g2d_end();
    }
    g2d_shutdown();
    return 0;
}
```

## Build demo (GUI/X11 required)
```sh
./magc examples/demo_game2d.mg -o build/demo_game2d
./build/demo_game2d
```
