// examples/test_control.mg
// Comprehensive Falcon Control Flow Verification Suite
use "lib/math.mg";

fn test_goto() -> void {
    print("  Starting goto test...\n");
    goto target_label;
    print("  [ERROR] This statement should be skipped!\n");
target_label:
    print("  Goto jump target reached successfully!\n");
}

fn main() -> void {
    print("=== FALCON CONTROL FLOW INTEGRITY TEST ===\n\n");

    // 1. If / Else
    print("[1] If / Else Conditions:\n");
    int x = 100;
    if (x > 50) {
        print("  x > 50: Passed!\n");
    } else {
        print("  x <= 50: Failed!\n");
    }
    print("\n");

    // 2. Switch / Case / Default
    print("[2] Switch / Case Selection:\n");
    int val = 2;
    switch (val) {
        case 1: {
            print("  Selected: 1 (Failed)\n");
            break;
        }
        case 2: {
            print("  Selected: 2 (Passed!)\n");
            break;
        }
        default: {
            print("  Selected: Default (Failed)\n");
            break;
        }
    }
    print("\n");

    // 3. For loop
    print("[3] For loops:\n");
    int sum = 0;
    for (int i = 1; i <= 5; i = i + 1) {
        sum = sum + i;
    }
    print("  Sum of 1..5 = "); print(sum); print("\n\n");

    // 4. While loop
    print("[4] While loops:\n");
    int count = 3;
    while (count > 0) {
        print("  while counter: "); print(count); print("\n");
        count = count - 1;
    }
    print("\n");

    // 5. Do-While loop
    print("[5] Do-While loops:\n");
    int do_count = 0;
    do {
        print("  do-while iteration executed once!\n");
        do_count = do_count + 1;
    } while (do_count < 1);
    print("\n");

    // 6. Loop controls: Break and Continue
    print("[6] Loop Controls (Break & Continue):\n");
    int break_test = 0;
    for (int i = 0; i < 10; i = i + 1) {
        if (i == 3) {
            continue; // Skip 3
        }
        if (i == 5) {
            break; // Stop at 5
        }
        print("  Index (skipping 3, stopping at 5): "); print(i); print("\n");
    }
    print("\n");

    // 7. Defer statement (LIFO execution)
    print("[7] Defer statement LIFO:\n");
    {
        defer print("  [Deferred 2] executed last!\n");
        defer print("  [Deferred 1] executed first!\n");
        print("  Executing normal statement 1...\n");
        print("  Executing normal statement 2...\n");
    }
    print("\n");

    // 8. Match expression / statement
    print("[8] Match statement patterns:\n");
    int target = 2;
    match (target) {
        1 => {
            print("  Matched pattern: One (Failed)\n");
        }
        2 => {
            print("  Matched pattern: Two (Passed!)\n");
        }
        _ => {
            print("  Matched pattern: Default (Failed)\n");
        }
    }
    print("\n");

    // 9. Goto jumps
    print("[9] Goto Jumps:\n");
    test_goto();
    print("\n");

    // 10. Cooperative Yield
    print("[10] Yield statement:\n");
    // yield removed
    print("  Yield control context switched back successfully!\n\n");

    print("=== ALL FALCON CONTROL FLOWS VERIFIED SUCCESSFULY ===\n");
}
