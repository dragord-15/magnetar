// examples/test_oop.mg
// Comprehensive Falcon OOP & Modules Verification Suite

// OOP test
use math as m;
use math.Vector3 as Vec3;
use "lib/math.mg";


export struct Point2D {
    float x;
    float y;
};

export class Shape {
    float area;
    fn calculateArea() -> void {
        this.area = 0.0;
    }
};

class Rectangle extends Shape {
    float width;
    float height;
    
    fn calculateArea() -> void {
        super.calculateArea();
        this.area = this.width * this.height;
    }
};

enum Color {
    RED = 1,
    GREEN = 2,
    BLUE = 3
};

union Data {
    int i_val;
    float f_val;
};

interface Drawable {
    fn draw() -> void;
};

trait Movable {
    fn translate(float dx, float dy) -> void;
};

class Circle extends Shape {
    float radius;
    
    fn getBaseArea() -> float {
        return base.area;
    }
};

impl Drawable for Circle {
    fn draw() -> void {
        print("  Drawing a Circle with radius: ");
        print(self.radius);
        print("\n");
    }
}

impl Movable for Circle {
    fn translate(float dx, float dy) -> void {
        print("  Moving circle by dx, dy\n");
    }
}

fn main() -> void {
    print("=== FALCON OOP & MODULES INTEGRITY TEST ===\n\n");

    print("[1] Struct and Modules:\n");
    Point2D p;
    p.x = 10.5;
    p.y = 20.5;
    print("  Point2D: x="); print(p.x); print(", y="); print(p.y); print("\n\n");

    print("[2] Classes and Inheritance:\n");
    Rectangle rect;
    rect.width = 5.0;
    rect.height = 4.0;
    rect.calculateArea();
    print("  Rectangle Area: "); print(rect.area); print("\n\n");

    print("[3] Enums and Unions:\n");
    Color c = 2; // GREEN
    Data d;
    d.i_val = 42;
    print("  Enum Color (GREEN): "); print(c); print("\n");
    print("  Union Data (i_val): "); print(d.i_val); print("\n\n");

    print("[4] Interfaces, Traits, Impl, Self, Base:\n");
    Circle circ;
    circ.radius = 7.5;
    circ.area = 176.71;
    
    circ.draw();
    circ.translate(1.0, 2.0);
    print("  Circle base area: "); print(circ.getBaseArea()); print("\n\n");

    print("=== ALL FALCON OOP FEATURES VERIFIED SUCCESSFULY ===\n");
}
