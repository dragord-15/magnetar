// demo_game2d.mg - Minimal 2D game demo using lib/game2d.mg
// Build: ./magc examples/demo_game2d.mg -o build/demo_game2d
// Run:   ./build/demo_game2d   (requires GUI/X11)

use "lib/gui.mg";
use "lib/game2d.mg";

fn main() -> int {
    if (g2d_init_window(800, 600, "Magnetar Game2D Demo") < 0) {
        return 1;
    }

    Camera2D cam = camera2d_new(800, 600);
    Sprite2D player = sprite2d_new(100, 100, 40, 40, gui_rgb(80, 200, 120));
    Sprite2D enemy = sprite2d_new(400, 300, 36, 36, gui_rgb(220, 80, 80));
    Input2D inp = input2d_new();
    Timer2D timer = timer2d_new();

    Tilemap2D tm = tilemap2d_new(20, 15, 40, 40);
    tilemap2d_set_color(&tm, 1, gui_rgb(70, 70, 90));
    tilemap2d_set_color(&tm, 2, gui_rgb(90, 120, 90));
    int x = 0;
    while (x < 20) { tilemap2d_set(&tm, x, 14, 1); x = x + 1; }
    tilemap2d_set(&tm, 5, 13, 2);
    tilemap2d_set(&tm, 6, 13, 2);
    tilemap2d_set(&tm, 12, 12, 2);

    int t = 0;
    while (g2d_running() == true) {
        g2d_begin();
        timer2d_tick(&timer);
        input2d_clear_dirs(&inp);
        input2d_update(&inp);
        if (inp.quit == 1) { break; }

        int speed = 4;
        if (inp.up == 1) { player.y = player.y - speed; }
        if (inp.down == 1) { player.y = player.y + speed; }
        if (inp.left == 1) { player.x = player.x - speed; }
        if (inp.right == 1) { player.x = player.x + speed; }

        // gentle auto-motion so demo is visibly alive even without input
        t = t + 1;
        enemy.x = 400 + (t % 200) - 100;
        if ((t / 120) % 2 == 0) { enemy.y = 300; } else { enemy.y = 320; }

        if (player.x < 0) { player.x = 0; }
        if (player.y < 0) { player.y = 0; }
        if (player.x > 760) { player.x = 760; }
        if (player.y > 560) { player.y = 560; }

        camera2d_follow(&cam, player.x + player.w / 2, player.y + player.h / 2, 1, 8);

        g2d_clear(gui_rgb(24, 28, 40));
        tilemap2d_draw(&tm, &cam);
        sprite2d_draw(&enemy, &cam);
        sprite2d_draw_outline(&player, &cam, gui_rgb(255, 255, 255));

        g2d_fill_rect(10, 10, 420, 28, gui_rgb(0, 0, 0));
        g2d_text(16, 16, "WASD/Arrows to move, ESC to quit", gui_rgb(230, 230, 230));
        if (sprite2d_collides(&player, &enemy) == true) {
            g2d_text(16, 40, "Collision!", gui_rgb(255, 220, 80));
        }

        g2d_end();
    }

    g2d_shutdown();
    return 0;
}
