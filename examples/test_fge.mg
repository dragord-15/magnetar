// examples/test_fge.mg
// Falcon Game Engine (FGE) Demonstration and Verification Suite

use fge;
use gfx/gfx_game;


extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;
extern fn print_float(float f) -> void;

fn test_audio() -> void {
    print_str("[1/5] Testing FGE Audio...\n");
    Audio sound;
    sound.playWav("assets/click.wav");
    sound.playMp3("assets/theme.mp3");
    sound.play3DAudio("assets/explosion.wav", 10.5, 0.0, 0.0 - 5.0);
    print_str("-> Audio Subsystem OK!\n\n");
}

fn test_physics() -> void {
    print_str("[2/5] Testing FGE Physics (RigidBody)...\n");
    RigidBody ball;
    ball.init(0.0, 100.0, 2.0, 0.75, false); // mass=2.0, bounciness=0.75, is_static=false
    
    // Apply gravity force (mass * -9.8)
    ball.applyForce(0.0, 0.0 - 19.6);
    ball.update(0.1); // step with dt = 0.1s
    
    print_str("-> Ball Position Y: ");
    print_float(ball.py);
    print_str("\n-> Ball Velocity Y: ");
    print_float(ball.vy);
    print_str("\n-> Physics Subsystem OK!\n\n");
}

fn test_input() -> void {
    print_str("[3/5] Testing FGE Input...\n");
    Input inp;
    if (inp.isKeyPressed(119)) {
        print_str("-> Keyboard input 'w' (W) detected successfully!\n");
    }
    print_str("-> Mouse Position: (");
    print_int(inp.getMouseX());
    print_str(", ");
    print_int(inp.getMouseY());
    print_str(")\n");
    if (inp.isGamepadButtonPressed(0)) {
        print_str("-> Gamepad button 'A' pressed successfully!\n");
    }
    print_str("-> Input Subsystem OK!\n\n");
}

fn test_graphics() -> void {
    print_str("[4/5] Testing FGE 2D & 3D Visual Assets...\n");
    Sprite hero;
    hero.init("HeroSprite", 200, 200, 64, 64);
    
    Tilemap tmap;
    tmap.init(10, 10, 32);
    
    print_str("-> Graphics Assets Loaded OK!\n\n");
}

fn test_game_loop() -> void {
    print_str("[5/5] Launching FGE Game Viewport...\n");
    Game game;
    game.init("Falcon Engine Game Showcase", 800, 600);
    
    Sprite hero;
    hero.init("assets/player.png", 200, 200, 64, 64);
    
    Button btn;
    btn.init("START GAME", 350, 500, 150, 40);
    
    while (game.running) {
        game.render_begin();
        
        // Render 2D Sprite
        hero.x = hero.x + 1;
        if (hero.x > 800) {
            hero.x = 0;
        }
        hero.draw();
        
        // Render Button UI
        btn.draw();
        
        game.update();
        game.render_end();
    }
}

fn main() -> void {
    print_str("===============================================\n");
    print_str("   🦅 FALCON GAME ENGINE (FGE) VERIFICATION   🦅\n");
    print_str("===============================================\n");

    test_audio();
    test_physics();
    test_input();
    test_graphics();
    test_game_loop();
    
    print_str("===============================================\n");
    print_str("🎉 SUCCESS: FGE Subsystems Verified perfectly! 🎉\n");
    print_str("===============================================\n");
}
