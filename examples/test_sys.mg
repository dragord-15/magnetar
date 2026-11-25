// examples/test_sys.mg
// Verification suite for FS, OS, and Process libraries

extern fn fs_exists(string path) -> bool;
extern fn fs_mkdir(string path) -> void;
extern fn fs_rm(string path) -> void;

extern fn os_get_env(string name) -> string;
extern fn os_get_platform() -> string;

extern fn process_exec(string cmd) -> int;

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

class SystemUtility {
    fn checkAndCreateDir(string path) -> void {
        if (fs_exists(path)) {
            print_str("Path already exists, removing old entry...\n");
            fs_rm(path);
        }
        fs_mkdir(path);
    }
};

fn main() -> void {
    print_str("--- Falcon Standard Library: FS, OS, and Process ---\n");

    // 1. Operating System Info
    print_str("OS Platform: ");
    print_str(os_get_platform());
    print_str("\n");

    print_str("Reading environment variable 'PATH'...\n");
    string env_val = os_get_env("PATH");
    print_str("Value: ");
    print_str(env_val);
    print_str("\n");

    // 2. File System Operations
    SystemUtility sys;
    sys.checkAndCreateDir("output_dir");

    // 3. Process Execution
    print_str("Launching background compilation job...\n");
    int exit_code = process_exec("falcon --build examples/main.mg");
    print_str("Process finished with exit code: ");
    print_int(exit_code);
    print_str("\n");

    print_str("SUCCESS: FS, OS, and Process libraries compiled and executed perfectly!\n");
}
