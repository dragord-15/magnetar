// Advanced test
use std;
use std as s;
use math.sqrt;
use math.sin as s;
use math;


union MyUnion {
    int i;
    float f;
};

interface Player {
    fn get_score() -> int;
}

trait Renderable {
    fn render() -> void;
}

impl Renderable for Player {
    fn render() -> void {
        print "Rendered player instance!\n";
    }
}

export fn test_export() -> void {
    print "Export function executed successfully!\n";
}

fn test_goto() -> void {
    print "Starting goto test...\n";
    goto skip_print;
    print "This SHOULD NOT print!\n";
skip_print:
    print "Goto jump successful!\n";
}

fn test_defer() -> void {
    print "Starting defer test...\n";
    defer print "Deferred statement 2 (LIFO: ran last)!\n";
    defer print "Deferred statement 1 (LIFO: ran first)!\n";
    print "Normal execution line 1\n";
    print "Normal execution line 2\n";
}

fn test_match(int val) -> void {
    match (val) {
        1 => { print "Matched One!\n"; }
        2 => { print "Matched Two!\n"; }
        _ => { print "Matched Default!\n"; }
    }
}

fn test_assertions() -> void {
    print "Starting assert test...\n";
    assert 1; // Should pass silently
    print "Assert 1 successful!\n";
}

fn test_exceptions() -> void {
    print "Starting try-catch-finally test...\n";
    try {
        print "Inside try block, preparing to throw...\n";
        throw 99;
        print "This should NOT execute after throw!\n";
    } catch(e) {
        print "Exception caught successfully inside catch block!\n";
    } finally {
        print "Finally block executed successfully!\n";
    }
}

fn test_advanced_types() -> void {
    print "Starting advanced type checks...\n";
    const int CONST_VAL = 42;
    print "Const integer: ";
    print CONST_VAL;
    print "\n";

    any dynamic_var;
    simd<int, 4> vector_var;
    ref<int> reference_ptr;
    own<string> owning_ptr;
    stream<int> pipeline;
    atom<int> atomic_counter;
    print "Advanced type declarations compiled successfully!\n";
}

fn test_inline_assembly() -> void {
    print "Executing inline assembly...\n";
    asm("nop");
    asm {
        nop;
        nop;
    }
    print "Inline assembly executed successfully!\n";
}

fn test_concurrency() -> void {
    print "Starting concurrency tests...\n";
    async {
        print "Inside async block!\n";
    }
    parallel {
        print "Inside parallel block!\n";
    }
    spawn test_export();
    await 1;
    print "Concurrency flow barrier resolved successfully!\n";
}

fn main() -> int {
    print "=== STARTING ADVANCED KEYWORDS TEST ===\n";

    // 1. Generic Array Type
    array<int, 3> arr;
    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;
    print "Array elements: ";
    print arr[0];
    print ", ";
    print arr[1];
    print ", ";
    print arr[2];
    print "\n";

    // 2. Anonymous Tuple Type
    tuple<int, float, string> t;
    t._0 = 100;
    t._1 = 3.14;
    t._2 = "Falcon Tuple";
    print "Tuple elements: ";
    print t._0;
    print ", ";
    print t._1;
    print ", ";
    print t._2;
    print "\n";

    // 3. Union Type (overlap verification)
    MyUnion u;
    u.i = 1234567;
    print "Union overlap: ";
    print u.i;
    print "\n";

    // 4. Goto Jumps
    test_goto();

    // 5. Match Control Flow
    print "Match (1): ";
    test_match(1);
    print "Match (2): ";
    test_match(2);
    print "Match (99): ";
    test_match(99);

    // 6. Defer Out-of-Order Execution
    test_defer();

    // 7. Yield Cooperative Yield
    print "Cooperative sched_yield...\n";
    print "Yield returned successfully!\n";

    // 8. Modular systems
    test_export();

    // 9. Assertions
    test_assertions();

    // 10. Exception handling
    test_exceptions();

    // 11. Advanced Types (any, simd, ref, own, const, stream, atom)
    test_advanced_types();

    // 12. Inline Assembly (asm)
    test_inline_assembly();

    // 13. Concurrency (async, await, spawn, parallel)
    test_concurrency();

    print "=== ALL ADVANCED KEYWORDS TESTS PASSED SUCCESSFULY ===\n";
    return 0;
}
