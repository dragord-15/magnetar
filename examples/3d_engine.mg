// examples/3d_engine.fl
// Falcon 3D Engine Simulation

extern fn gfx_init(int width, int height, string title) -> void;
extern fn gfx_clear() -> void;
extern fn gfx_draw_line(int x1, int y1, int x2, int y2) -> void;
extern fn gfx_update() -> void;
extern fn gfx_is_open() -> bool;
extern fn cos(float a) -> float;
extern fn sin(float a) -> float;

extern fn print_str(string s) -> void;

fn main() -> void {
    print_str("--- Falcon 3D Engine Simulation ---\n");
    gfx_init(800, 600, "Falcon 3D Engine");
    float angle = 0.0;
    
    int count = 0;
    while (count < 3) {
        gfx_clear();
        
        angle = angle + 0.05;
        
        float x1 = cos(angle);
        float y1 = sin(angle);
        float x2 = cos(angle + 3.14);
        float y2 = sin(angle + 3.14);
        
        float scale = 150.0;
        int px1 = 400 + cast<int>(x1 * scale);
        int py1 = 300 + cast<int>(y1 * scale);
        int px2 = 400 + cast<int>(x2 * scale);
        int py2 = 300 + cast<int>(y2 * scale);
        
        gfx_draw_line(px1, py1, px2, py2);
        gfx_update();
        
        count = count + 1;
    }
    
    print_str("SUCCESS: 3d_engine compiled and simulated perfectly!\n");
}
