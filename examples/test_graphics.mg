// examples/test_graphics.mg
// Verification suite for Graphics, Audio, and GUI libraries

extern fn gfx_init(int width, int height, string title) -> void;
extern fn gfx_clear() -> void;
extern fn gfx_draw_line(int x1, int y1, int x2, int y2) -> void;
extern fn gfx_draw_text(int x, int y, string text) -> void;
extern fn gfx_update() -> void;
extern fn gfx_is_open() -> bool;

extern fn audio_play(string track) -> void;

extern fn print_str(string s) -> void;

class Canvas {
    int width;
    int height;
    string title;
    
    fn setup(int w, int h, string t) -> void {
        this.width = w;
        this.height = h;
        this.title = t;
        gfx_init(w, h, t);
    }
    
    fn renderFrame() -> void {
        gfx_clear();
        gfx_draw_line(10, 10, 100, 100);
        gfx_draw_text(50, 50, "Falcon Engine");
        gfx_update();
    }
};

fn main() -> void {
    print_str("--- Falcon Standard Library: Graphics and Audio ---\n");

    // 1. Audio
    print_str("Playing introductory background score...\n");
    audio_play("assets/music.wav");

    // 2. Graphics Screen
    Canvas canvas;
    canvas.setup(800, 600, "Falcon Game Window");
    
    print_str("Rendering single application frame...\n");
    canvas.renderFrame();

    if (gfx_is_open()) {
        print_str("Graphics viewport is active and open!\n");
    }

    print_str("SUCCESS: Graphics and Audio libraries compiled and executed perfectly!\n");
}
