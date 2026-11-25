// ============================================================================
// Magnetar Security Library: Memory Hardening & Anti-Forensics
// File: lib/security/secure_mem.mg
// ============================================================================

use "lib/string.mg";

// Constant-time string comparison to prevent timing side-channel attacks.
// Standard string comparison terminates early on first mismatch, leaking info.
fn secure_mem_compare(string a, string b) -> bool {
    let pa = cast<char*>(a);
    let pb = cast<char*>(b);
    
    if (pa == pb) {
        return true;
    }
    if (pa == null || pb == null) {
        return false;
    }
    
    let len_a = str_len(a);
    let len_b = str_len(b);
    
    let diff = 0;
    if (len_a != len_b) {
        diff = 1;
    }
    
    let n = len_a;
    if (len_b < n) {
        n = len_b;
    }
    
    let i = 0;
    while (i < n) {
        let ca = cast<int>(*(pa + i)) & 255;
        let cb = cast<int>(*(pb + i)) & 255;
        diff = diff | (ca ^ cb);
        i = i + 1;
    }
    
    return diff == 0;
}

// Securely scrub memory buffer before releasing it, overwriting with zeroes
// so sensitive keys, credentials, or tokens do not remain in memory.
fn secure_memzero(char* ptr, int size) -> void {
    if (ptr == null || size <= 0) {
        return;
    }
    let i = 0;
    while (i < size) {
        *(ptr + i) = 0;
        i = i + 1;
    }
}

// Canary guard constant to detect buffer overrun
const int CANARY_MAGIC = 3735928559; // 0xDEADBEEF in decimal

struct CanaryBuffer {
    int canary_front;
    int payload_size;
    char* data;
    int canary_back;
}

// Allocate a buffer protected with front and back canaries.
fn secure_alloc_protected(int size) -> CanaryBuffer {
    let cb: CanaryBuffer;
    cb.canary_front = CANARY_MAGIC;
    cb.payload_size = size;
    cb.data = alloc<char>(size);
    secure_memzero(cb.data, size);
    cb.canary_back = CANARY_MAGIC;
    return cb;
}

// Check whether buffer bounds were compromised by memory corruption
fn secure_check_integrity(CanaryBuffer buf) -> bool {
    if (buf.canary_front != CANARY_MAGIC) {
        return false;
    }
    if (buf.canary_back != CANARY_MAGIC) {
        return false;
    }
    return true;
}

// Safely wipe and free protected buffer
fn secure_free_protected(CanaryBuffer buf) -> void {
    if (buf.data != null) {
        secure_memzero(buf.data, buf.payload_size);
        free(buf.data);
    }
}
