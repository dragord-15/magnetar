// examples/game.fn
// Falcon Game Engine Simulation

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;
extern fn print_float(float f) -> void;

class Entity {
    float px;
    float py;
    float pz;
    
    fn translate(float dx, float dy, float dz) -> void {
        this.px = this.px + dx;
        this.py = this.py + dy;
        this.pz = this.pz + dz;
    }
};

class Player extends Entity {
    string name;
    int health;
    
    fn takeDamage(int amount) -> void {
        this.health = this.health - amount;
        if (this.health < 0) {
            this.health = 0;
        }
    }
};

fn main() -> void {
    print_str("--- Falcon Game Simulation Running ---\n");
    Player hero;
    hero.name = "Batal";
    hero.health = 100;
    hero.px = 0.0;
    hero.py = 0.0;
    hero.pz = 0.0;
    
    hero.translate(1.5, 0.0, 2.5);
    hero.takeDamage(15);
    
    print_str("Player Name: ");
    print_str(hero.name);
    print_str("\nPlayer Health: ");
    print_int(hero.health);
    print_str("\nPlayer Position: (");
    print_float(hero.px);
    print_str(", ");
    print_float(hero.py);
    print_str(", ");
    print_float(hero.pz);
    print_str(")\n");
    
    print_str("SUCCESS: game compiled and executed perfectly!\n");
}
