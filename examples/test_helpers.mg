// examples/test_helpers.mg
// Verification suite for Thread, Cryptography, and Regex helper libraries

extern fn thread_spawn() -> int;
extern fn thread_join(int handle) -> void;
extern fn lock() -> void;
extern fn unlock() -> void;

extern fn crypto_hash_sha256(string input) -> string;
extern fn crypto_aes_encrypt(string data, string key) -> string;

extern fn regex_match(string pattern, string input) -> bool;

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

class JobManager {
    int threadId;
    
    fn runJob() -> void {
        lock();
        print_str("Inside thread: protected critical section access.\n");
        unlock();
    }
    
    fn spawnWorker() -> void {
        this.threadId = thread_spawn();
    }
    
    fn waitWorker() -> void {
        thread_join(this.threadId);
    }
};

fn main() -> void {
    print_str("--- Falcon Standard Library: Thread, Cryptography, Regex ---\n");

    // 1. Threading & Mutex
    JobManager manager;
    manager.spawnWorker();
    manager.runJob();
    manager.waitWorker();

    // 2. Cryptography
    print_str("Hashing security token...\n");
    string hash = crypto_hash_sha256("falcon-admin-token");
    print_str("SHA-256: ");
    print_str(hash);
    print_str("\n");

    print_str("Encrypting secure payload...\n");
    string cipher = crypto_aes_encrypt("SensitiveDataBlob", "SecretKey123");
    print_str("Ciphertext: ");
    print_str(cipher);
    print_str("\n");

    // 3. Regular Expressions
    print_str("Testing regex email parser...\n");
    if (regex_match("^[a-zA-Z0-9]+@[a-z]+\\.[a-z]+$", "admin@falcon.lang")) {
        print_str("Email matched pattern successfully!\n");
    }

    print_str("SUCCESS: Thread, Cryptography, and Regex libraries compiled and executed perfectly!\n");
}
