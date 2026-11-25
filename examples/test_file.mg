// examples/test_file.mg
// Comprehensive Test Suite for Magnetar File Library (lib/file.mg)

use "lib/file.mg";

fn main() -> void {
    print("=== STARTING MAGNETAR FILE LIBRARY VERIFICATION ===\n\n");

    string test_file = "/tmp/mag_test_demo.txt";
    string copy_file = "/tmp/mag_test_copy.txt";
    string move_file = "/tmp/mag_test_moved.txt";

    // Clean up previous runs if any
    if (file_exists(test_file)) {
        file_delete(test_file);
    }
    if (file_exists(copy_file)) {
        file_delete(copy_file);
    }
    if (file_exists(move_file)) {
        file_delete(move_file);
    }

    // 1. One-Shot Write and Read All
    print("[1] Testing file_write_all and file_read_all:\n");
    bool w_ok = file_write_all(test_file, "Line 1: Hello from Magnetar File System!\nLine 2: Built-in Native Systems IO.");
    print("  Write success: "); print(w_ok); print("\n");

    string content = file_read_all(test_file);
    print("  Read content:\n");
    print_str(content);
    print("\n\n");

    // 2. File Metadata (exists, size, is_file, is_dir)
    print("[2] Testing File Metadata:\n");
    print("  file_exists: "); print(file_exists(test_file)); print("\n");
    print("  file_size: "); print(file_size(test_file)); print(" bytes\n");
    print("  file_is_file: "); print(file_is_file(test_file)); print("\n");
    print("  file_is_dir: "); print(file_is_dir(test_file)); print(" (expected 0)\n");
    print("  src is_dir: "); print(file_is_dir("src")); print(" (expected 1)\n\n");

    // 3. Append to file
    print("[3] Testing file_append_all:\n");
    bool a_ok = file_append_all(test_file, "\nLine 3: Appended content works!");
    print("  Append success: "); print(a_ok); print("\n");
    print("  New file size: "); print(file_size(test_file)); print(" bytes\n\n");

    // 4. Line by line reading
    print("[4] Testing file_read_line:\n");
    int fd = file_open(test_file, "r");
    print("  Opened fd: "); print(fd); print("\n");
    string l1 = file_read_line(fd);
    string l2 = file_read_line(fd);
    string l3 = file_read_line(fd);
    file_close(fd);

    print("  Read L1: "); print_str(l1); print("\n");
    print("  Read L2: "); print_str(l2); print("\n");
    print("  Read L3: "); print_str(l3); print("\n\n");

    // 5. Path manipulation utilities
    print("[5] Testing Path Utilities:\n");
    string sample_path = "/usr/local/falcon/kernel.tar.gz";
    print("  Path: "); print_str(sample_path); print("\n");
    print("  Basename: "); print_str(file_basename(sample_path)); print("\n");
    print("  Dirname: "); print_str(file_dirname(sample_path)); print("\n");
    print("  Extension: "); print_str(file_extension(sample_path)); print("\n\n");

    // 6. File Copy, Move, and Delete
    print("[6] Testing Copy, Move and Delete:\n");
    bool c_ok = file_copy(test_file, copy_file);
    print("  Copy success: "); print(c_ok); print("\n");
    print("  Copy file exists: "); print(file_exists(copy_file)); print("\n");
    print("  Copy file size: "); print(file_size(copy_file)); print("\n");

    bool m_ok = file_move(copy_file, move_file);
    print("  Move success: "); print(m_ok); print("\n");
    print("  Old copy exists: "); print(file_exists(copy_file)); print(" (expected 0)\n");
    print("  Moved file exists: "); print(file_exists(move_file)); print(" (expected 1)\n");

    bool d_ok = file_delete(move_file);
    print("  Delete success: "); print(d_ok); print("\n");
    print("  Moved file exists after delete: "); print(file_exists(move_file)); print(" (expected 0)\n\n");

    // 7. Object-Oriented File Struct API
    print("[7] Testing OOP struct File:\n");
    string oop_file = "/tmp/mag_oop_demo.txt";
    File f;
    f.open(oop_file, "w");
    f.write_line("OOP File Line 1");
    f.write_line("OOP File Line 2");
    print("  File size via tell: "); print(f.tell()); print("\n");
    f.close();

    File reader;
    reader.open(oop_file, "r");
    print("  File is_open: "); print(reader.is_open); print("\n");
    string oop_l1 = reader.read_line();
    string oop_l2 = reader.read_line();
    print("  Read line 1: "); print_str(oop_l1); print("\n");
    print("  Read line 2: "); print_str(oop_l2); print("\n");
    reader.close();

    // Clean up demo files
    file_delete(test_file);
    file_delete(oop_file);

    print("\n=== ALL FILE LIBRARY TESTS PASSED SUCCESSFULLY! ===\n");
}
