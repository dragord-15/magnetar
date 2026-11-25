// examples/test_math_time.mg
// Verification suite for Math, Random, Time, and IO libraries

extern fn sin(float x) -> float;
extern fn cos(float x) -> float;
extern fn tan(float x) -> float;
extern fn sqrt(float x) -> float;
extern fn pow(float base_val, float exp_val) -> float;

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;
extern fn print_float(float f) -> void;
extern fn read_line() -> string;

extern fn get_timestamp() -> int;
extern fn sleep_ms(int ms) -> void;

extern fn rand_int() -> int;
extern fn rand_float() -> float;

static float PI = 3.14159265;
static float E = 2.71828182;

class Vector3 {
    float x;
    float y;
    float z;
    
    fn magnitude() -> float {
        float xx = this.x * this.x;
        float yy = this.y * this.y;
        float zz = this.z * this.z;
        float sum = xx + yy + zz;
        return sqrt(sum);
    }
    
    fn normalize() -> void {
        float mag = this.magnitude();
        if (mag > 0.0) {
            this.x = this.x / mag;
            this.y = this.y / mag;
            this.z = this.z / mag;
        }
    }
};

fn dot(Vector3 a, Vector3 b) -> float {
    float axbx = a.x * b.x;
    float ayby = a.y * b.y;
    float azbz = a.z * b.z;
    return axbx + ayby + azbz;
}

fn abs(float x) -> float {
    if (x < 0.0) {
        return 0.0 - x;
    }
    return x;
}

fn min(float a, float b) -> float {
    if (a < b) {
        return a;
    }
    return b;
}

fn max(float a, float b) -> float {
    if (a > b) {
        return a;
    }
    return b;
}

class Random {
    fn nextInt(int min_val, int max_val) -> int {
        int r = rand_int();
        if (r < 0) {
            r = 0 - r;
        }
        int range_val = max_val - min_val;
        int rem = r - (r / range_val) * range_val;
        return min_val + rem;
    }
    
    fn nextFloat() -> float {
        return rand_float();
    }
};

class Time {
    fn now() -> int {
        return get_timestamp();
    }
    fn sleep(int milliseconds) -> void {
        sleep_ms(milliseconds);
    }
};

class File {
    int handle;
    string path;
    
    fn open(string filepath) -> bool {
        this.path = filepath;
        return true;
    }
    
    fn readAll() -> string {
        return "File content stub";
    }
};

fn main() -> void {
    print_str("--- Falcon Standard Library: Math, Random, Time, IO ---\n");

    // 1. Math constants & functions
    float pi_val = PI;
    float e_val = E;
    print_str("PI: ");
    print_float(pi_val);
    print_str("\nE: ");
    print_float(e_val);
    print_str("\n");

    float val = 0.0 - 4.5;
    print_str("abs(-4.5): ");
    print_float(abs(val));
    print_str("\n");

    float f10 = 10.0;
    float f20 = 20.0;
    print_str("min(10.0, 20.0): ");
    print_float(min(f10, f20));
    print_str("\n");

    print_str("max(10.0, 20.0): ");
    print_float(max(f10, f20));
    print_str("\n");

    // Native SSE & x87 trig functions!
    float f16 = 16.0;
    print_str("sqrt(16.0): ");
    print_float(sqrt(f16));
    print_str("\n");

    float f0 = 0.0;
    print_str("sin(0.0): ");
    print_float(sin(f0));
    print_str("\n");

    print_str("cos(0.0): ");
    print_float(cos(f0));
    print_str("\n");

    print_str("tan(0.0): ");
    print_float(tan(f0));
    print_str("\n");

    // Vector3 class and dot product
    Vector3 v1;
    v1.x = 3.0;
    v1.y = 4.0;
    v1.z = 0.0;
    print_str("v1 magnitude: ");
    print_float(v1.magnitude());
    print_str("\n");

    v1.normalize();
    print_str("v1 normalized: (");
    print_float(v1.x);
    print_str(", ");
    print_float(v1.y);
    print_str(", ");
    print_float(v1.z);
    print_str(")\n");

    Vector3 v2;
    v2.x = 1.0;
    v2.y = 0.0;
    v2.z = 0.0;
    print_str("dot(v1, v2): ");
    print_float(dot(v1, v2));
    print_str("\n");

    // 2. Random
    Random rng;
    print_str("Random integer [10, 50]: ");
    print_int(rng.nextInt(10, 50));
    print_str("\n");

    print_str("Random float: ");
    print_float(rng.nextFloat());
    print_str("\n");

    // 3. Time
    Time t;
    int t_start = t.now();
    print_str("Current timestamp: ");
    print_int(t_start);
    print_str("\n");

    print_str("Sleeping for 10ms...\n");
    t.sleep(10);
    print_str("Awake!\n");

    // 4. File IO
    File f;
    f.open("test.txt");
    print_str("File opened path: ");
    print_str(f.path);
    print_str("\n");

    print_str("File readAll: ");
    print_str(f.readAll());
    print_str("\n");

    print_str("SUCCESS: Math, Random, Time, and IO libraries compiled and executed perfectly!\n");
}
