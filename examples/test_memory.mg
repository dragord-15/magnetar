// ── Test Point Structure ──
struct Point {
    int x;
    int y;
}

// ── Test Function ──
fn main() -> void {
    print "=== STARTING ADVANCED MEMORY MANAGEMENT TEST ===\n";

    // 1. Raw pointers & Standard pointers
    int x = 42;
    int* p = &x;
    print "Value of x through pointer: ";
    print *p;
    print "\n";

    *p = 100;
    print "Modified x through pointer: ";
    print x;
    print "\n";

    // 2. Variable named 'ptr' (Keyword Conflict Test)
    int ptr = 999;
    print "Variable named 'ptr' value: ";
    print ptr;
    print "\n";

    // 3. Generic ownership and reference types syntax
    int y = 500;
    ref<int> r = &y;
    print "Value of y through ref<int>: ";
    print *r;
    print "\n";

    // 4. Memory Allocation and Deallocation (alloc / free)
    print "Allocating heap array of 5 integers...\n";
    int* arr = alloc<int>(5);
    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;
    arr[3] = 40;
    arr[4] = 50;

    print "Heap array values: ";
    print arr[0];
    print ", ";
    print arr[1];
    print ", ";
    print arr[2];
    print ", ";
    print arr[3];
    print ", ";
    print arr[4];
    print "\n";

    print "Freeing heap array...\n";
    free(arr);

    // 5. Structures & Dynamic Instantiation (new / delete)
    print "Instantiating a Point struct on the heap...\n";
    Point* p1 = new Point;
    p1.x = 777;
    p1.y = 888;

    print "Point members: x=";
    print p1.x;
    print ", y=";
    print p1.y;
    print "\n";

    // 6. Ownership Move Semantics
    print "Moving ownership of Point p1 to p2...\n";
    Point* p2 = move p1;
    
    // Check that p1 is now null
    if (p1 == null) {
        print "Verified: p1 is now null!\n";
    }

    print "Accessing Point through p2: x=";
    print p2.x;
    print ", y=";
    print p2.y;
    print "\n";

    // 7. Copy / Clone Semantics (Dynamic cloning)
    print "Cloning Point p2 to p3...\n";
    Point* p3 = clone p2;
    print "Cloned Point p3: x=";
    print p3.x;
    print ", y=";
    print p3.y;
    print "\n";

    print "Modifying cloned Point p3...\n";
    p3.x = 55555;
    print "Original p2.x: ";
    print p2.x;
    print " (unchanged)\n";
    print "Cloned p3.x: ";
    print p3.x;
    print " (modified)\n";

    // 8. Delete / Free dynamic structures
    print "Deleting dynamic structures...\n";
    delete p2;
    delete p3;

    print "=== ALL MEMORY TESTS PASSED SUCCESSFULY ===\n";
}
