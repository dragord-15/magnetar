# lib/game3d.mg

Software 3D renderer and math utilities built on `lib/gui.mg`.

## Features
- Math: `Vec3/Vec4/Mat4`, vector ops, matrix transforms, projection helpers
- Camera: `Camera3D`, `camera3d_view_matrix`
- Frame: `g3d_init`, `g3d_clear`, `g3d_present`, `g3d_shutdown`
- Mesh: `Mesh3D`, `mesh3d_new`, `mesh3d_make_cube`, `mesh3d_model_matrix`
- Rendering: `g3d_draw_mesh_wire`, `g3d_draw_mesh_flat` (painter's sort + flat shading/backface cull)

## Example
```mg
use "lib/gui.mg";
use "lib/game3d.mg";

fn main() -> int {
    g3d_init(800, 600);
    Mesh3D cube = mesh3d_make_cube(2.0);
    Camera3D cam = camera3d_new(vec3(0.0, 0.0, 6.0));
    Vec3 light = vec3(0.4, 0.7, 1.0);
    while (g3d_close_requested() == 0) {
        cube.rot.y = cube.rot.y + 0.03;
        g3d_clear(gui_rgb(16,18,28));
        g3d_draw_mesh_flat(&cube, &cam, light);
        g3d_present();
    }
    g3d_shutdown();
    return 0;
}
```

## Build demo (GUI/X11 required)
```sh
./magc examples/demo_game3d.mg -o build/demo_game3d
./build/demo_game3d
```
