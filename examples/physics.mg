// examples/physics.fn
// Falcon Physics Simulation

extern fn print_str(string s) -> void;
extern fn print_float(float f) -> void;

class Particle {
    float px; float py; float pz;
    float vx; float vy; float vz;
    float mass;
    
    fn applyForce(float fx, float fy, float fz, float dt) -> void {
        float ax = fx / this.mass;
        float ay = fy / this.mass;
        float az = fz / this.mass;
        
        this.vx = this.vx + ax * dt;
        this.vy = this.vy + ay * dt;
        this.vz = this.vz + az * dt;
        
        this.px = this.px + this.vx * dt;
        this.py = this.py + this.vy * dt;
        this.pz = this.pz + this.vz * dt;
    }
};

fn main() -> void {
    print_str("--- Falcon Physics Simulation Running ---\n");
    Particle p;
    p.px = 0.0; p.py = 100.0; p.pz = 0.0;
    p.vx = 0.0; p.vy = 0.0; p.vz = 0.0;
    p.mass = 2.5;
    
    float gx = 0.0;
    float gy = 0.0 - 9.81;
    float gz = 0.0;
    float dt = 0.016;
    
    print_str("Starting gravity simulation (mass: 2.5kg, start height: 100m)...\n");
    
    int count = 0;
    while (count < 10) {
        // Apply force due to gravity: F = m * g
        float fx = p.mass * gx;
        float fy = p.mass * gy;
        float fz = p.mass * gz;
        
        p.applyForce(fx, fy, fz, dt);
        
        print_str("Step ");
        print_str(" -> Y position: ");
        print_float(p.py);
        print_str(", Velocity Y: ");
        print_float(p.vy);
        print_str("\n");
        
        count = count + 1;
    }
    
    print_str("SUCCESS: physics compiled and executed perfectly!\n");
}
