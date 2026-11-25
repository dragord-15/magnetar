// =============================================================================
// random.mg — Random number generation for Magnetar
// =============================================================================
// Provides:
//   - Fast PRNG (xorshift64*) seeded from kernel entropy
//   - Secure random (from sys_getrandom)
//   - Distributions: uniform, range, normal
//   - Utilities: shuffle, choice, coin_flip
//
// Usage:
//   use "utils/random";
//   random_seed();
//   let n = random_int(1, 100);
//   let f = random_float();
//   let s = random_secure_hex(16);
// =============================================================================

// -----------------------------------------------------------------------------
// State (PRNG)
// -----------------------------------------------------------------------------

// xorshift64* state — must be non-zero
struct RngState {
    int state;
}

// Global state (simple, single-threaded)
let global_rng: RngState;
let global_seeded: bool = false;

// -----------------------------------------------------------------------------
// Seeding
// -----------------------------------------------------------------------------

// Seed from kernel entropy (sys_getrandom)
fn random_seed() -> void {
    let buf = alloc<char>(8);
    let n = sys_getrandom(buf, 8, 0);  // flags=0
    if (n != 8) {
        // Fallback: use time
        let t = get_timestamp();
        global_rng.state = t;
    } else {
        // Pack 8 bytes into int64
        let s = 0;
        let i = 0;
        while (i < 8) {
            s = s | ((buf[i] & 255) << (i * 8));
            i = i + 1;
        }
        global_rng.state = s;
    }
    free(buf);

    // xorshift requires non-zero
    if (global_rng.state == 0) {
        global_rng.state = 88172645463325252;  // known non-zero constant
    }
    global_seeded = true;
}

// Seed explicitly (for reproducible tests)
fn random_seed_with(int seed) -> void {
    global_rng.state = seed;
    if (global_rng.state == 0) {
        global_rng.state = 88172645463325252;
    }
    global_seeded = true;
}

// Auto-seed if not seeded
fn ensure_seeded() -> void {
    if (!global_seeded) {
        random_seed();
    }
}

// -----------------------------------------------------------------------------
// Core PRNG — xorshift64*
// -----------------------------------------------------------------------------

// Fast, high-quality PRNG. Returns next 64-bit value.
fn random_next_u64() -> int {
    ensure_seeded();
    let x = global_rng.state;
    x = x ^ (x >> 12);
    x = x ^ (x << 25);
    x = x ^ (x >> 27);
    global_rng.state = x;
    // xorshift64* multiplier: 2685821657736338717
    // Note: may overflow, but that's fine for PRNG
    return x * 2685821657736338717;
}

// -----------------------------------------------------------------------------
// Basic random
// -----------------------------------------------------------------------------

// Random int in [0, INT_MAX)
fn random_int() -> int {
    let v = random_next_u64();
    if (v < 0) { v = -v; }
    return v;
}

// Random int in [min, max) — exclusive max
fn random_int_range(int min, int max) -> int {
    if (max <= min) { return min; }
    let span = max - min;
    let r = random_next_u64();
    if (r < 0) { r = -r; }
    return min + (r % span);
}

// Random int in [min, max] — inclusive
fn random_int_inclusive(int min, int max) -> int {
    return random_int_range(min, max + 1);
}

// Random float in [0.0, 1.0)
fn random_float() -> float {
    let r = random_next_u64();
    if (r < 0) { r = -r; }
    // Divide by 2^63 (max positive int64)
    return (r as float) / 9223372036854775808.0;
}

// Random float in [min, max)
fn random_float_range(float min, float max) -> float {
    return min + (random_float() * (max - min));
}

// Random bool (50/50)
fn random_bool() -> bool {
    return (random_next_u64() & 1) == 1;
}

// -----------------------------------------------------------------------------
// Secure random (from kernel)
// -----------------------------------------------------------------------------

// Fill buffer with secure random bytes. Returns number of bytes read.
fn random_secure_bytes(char* buf, int n) -> int {
    return sys_getrandom(buf, n, 0);
}

// Secure random int (slower, but cryptographically safe)
fn random_secure_int() -> int {
    let buf = alloc<char>(8);
    random_secure_bytes(buf, 8);
    let v = 0;
    let i = 0;
    while (i < 8) {
        v = v | ((buf[i] & 255) << (i * 8));
        i = i + 1;
    }
    free(buf);
    if (v < 0) { v = -v; }
    return v;
}

// Secure random hex string of length n (2n chars)
fn random_secure_hex(int n) -> string {
    let buf = alloc<char>(n);
    random_secure_bytes(buf, n);
    let hex = alloc<char>(n * 2 + 1);
    let i = 0;
    while (i < n) {
        let b = buf[i] & 255;
        hex[i * 2] = hex_char(b >> 4);
        hex[i * 2 + 1] = hex_char(b & 15);
        i = i + 1;
    }
    hex[n * 2] = '\0';
    free(buf);
    return hex;
}

fn hex_char(int v) -> char {
    if (v < 10) { return '0' + v; }
    return 'a' + (v - 10);
}

// -----------------------------------------------------------------------------
// Utilities
// -----------------------------------------------------------------------------

// Random choice from array
fn random_choice_int(dyn<int> arr) -> int {
    if (len(arr) == 0) { return 0; }
    let idx = random_int_range(0, len(arr));
    return arr[idx];
}

fn random_choice_string(dyn<string> arr) -> string {
    if (len(arr) == 0) { return ""; }
    let idx = random_int_range(0, len(arr));
    return arr[idx];
}

// Shuffle array in place (Fisher-Yates)
fn random_shuffle_int(dyn<int> arr) -> void {
    let n = len(arr);
    let i = n - 1;
    while (i > 0) {
        let j = random_int_range(0, i + 1);
        let tmp = arr[i];
        arr[i] = arr[j];
        arr[j] = tmp;
        i = i - 1;
    }
}

fn random_shuffle_string(dyn<string> arr) -> void {
    let n = len(arr);
    let i = n - 1;
    while (i > 0) {
        let j = random_int_range(0, i + 1);
        let tmp = arr[i];
        arr[i] = arr[j];
        arr[j] = tmp;
        i = i - 1;
    }
}

// Coin flip with probability p (0.0 to 1.0)
fn random_chance(float p) -> bool {
    return random_float() < p;
}

// Random normal (Gaussian) — Box-Muller
fn random_normal(float mean, float stddev) -> float {
    let u1 = random_float();
    let u2 = random_float();
    // Avoid log(0)
    if (u1 == 0.0) { u1 = 0.0000001; }
    let z = sqrt(-2.0 * log(u1)) * cos(2.0 * 3.141592653589793 * u2);
    return mean + z * stddev;
}

// -----------------------------------------------------------------------------
// Testing
// -----------------------------------------------------------------------------

// Test reproducibility: same seed → same sequence
fn random_test_reproducible() -> bool {
    random_seed_with(12345);
    let a = random_int();
    random_seed_with(12345);
    let b = random_int();
    return a == b;
}

// Test range: all values must be in [min, max)
fn random_test_range(int min, int max) -> bool {
    let i = 0;
    while (i < 1000) {
        let v = random_int_range(min, max);
        if (v < min || v >= max) { return false; }
        i = i + 1;
    }
    return true;
}