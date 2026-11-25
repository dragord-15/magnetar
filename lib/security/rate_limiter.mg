// ============================================================================
// Magnetar Security Library: Rate Limiter & Brute-Force Defense
// File: lib/security/rate_limiter.mg
// Implements request throttling and IP ban management (fail2ban style)
// ============================================================================

use "lib/string.mg";

const int MAX_RATE_LIMIT_ENTRIES = 32;

struct SecurityGovernor {
    int max_requests;
    int window_seconds;
    int ban_duration_seconds;
    int entry_count;
    string* ips;
    int* counts;
    int* start_times;
    int* is_banned;
    int* ban_expires;
}

// Allocates and initializes a new Security Governor instance on heap
fn governor_create(int max_req, int window_sec, int ban_duration) -> SecurityGovernor* {
    let gov = alloc<SecurityGovernor>(1);
    gov.max_requests = max_req;
    gov.window_seconds = window_sec;
    gov.ban_duration_seconds = ban_duration;
    gov.entry_count = 0;
    
    gov.ips = alloc<string>(MAX_RATE_LIMIT_ENTRIES);
    gov.counts = alloc<int>(MAX_RATE_LIMIT_ENTRIES);
    gov.start_times = alloc<int>(MAX_RATE_LIMIT_ENTRIES);
    gov.is_banned = alloc<int>(MAX_RATE_LIMIT_ENTRIES);
    gov.ban_expires = alloc<int>(MAX_RATE_LIMIT_ENTRIES);
    
    for (int i = 0; i < MAX_RATE_LIMIT_ENTRIES; i = i + 1) {
        gov.ips[i] = "";
        gov.counts[i] = 0;
        gov.start_times[i] = 0;
        gov.is_banned[i] = 0;
        gov.ban_expires[i] = 0;
    }
    return gov;
}

// Releases governor memory
fn governor_destroy(SecurityGovernor* gov) -> void {
    if (gov != null) {
        free(gov.ips);
        free(gov.counts);
        free(gov.start_times);
        free(gov.is_banned);
        free(gov.ban_expires);
        free(gov);
    }
}

// Finds entry index for IP, or returns -1
fn _governor_find_ip(SecurityGovernor* gov, string ip) -> int {
    for (int i = 0; i < gov.entry_count; i = i + 1) {
        if (str_equals(gov.ips[i], ip)) {
            return i;
        }
    }
    return -1;
}

// Checks if request from IP should be allowed (returns true) or blocked (returns false)
// current_time is a Unix timestamp (seconds)
fn governor_allow_request(SecurityGovernor* gov, string ip, int current_time) -> bool {
    if (gov == null) {
        return true;
    }
    
    let idx = _governor_find_ip(gov, ip);
    
    // Check if new IP
    if (idx < 0) {
        if (gov.entry_count >= MAX_RATE_LIMIT_ENTRIES) {
            return true; // Table limit reached, permit safely
        }
        idx = gov.entry_count;
        gov.ips[idx] = ip;
        gov.counts[idx] = 1;
        gov.start_times[idx] = current_time;
        gov.is_banned[idx] = 0;
        gov.ban_expires[idx] = 0;
        gov.entry_count = gov.entry_count + 1;
        return true;
    }
    
    // Check if currently banned
    if (gov.is_banned[idx] == 1) {
        if (current_time < gov.ban_expires[idx]) {
            return false; // Still serving ban
        } else {
            // Ban expired: reset
            gov.is_banned[idx] = 0;
            gov.counts[idx] = 1;
            gov.start_times[idx] = current_time;
            return true;
        }
    }
    
    // Check sliding window
    let elapsed = current_time - gov.start_times[idx];
    if (elapsed > gov.window_seconds) {
        // Window expired, start new window
        gov.start_times[idx] = current_time;
        gov.counts[idx] = 1;
        return true;
    }
    
    // Within current window: increment request count
    gov.counts[idx] = gov.counts[idx] + 1;
    
    // If exceeded rate limit: trigger automated ban
    if (gov.counts[idx] > gov.max_requests) {
        gov.is_banned[idx] = 1;
        gov.ban_expires[idx] = current_time + gov.ban_duration_seconds;
        return false;
    }
    
    return true;
}

// Check if an IP is currently blacklisted
fn governor_is_banned(SecurityGovernor* gov, string ip, int current_time) -> bool {
    if (gov == null) {
        return false;
    }
    let idx = _governor_find_ip(gov, ip);
    if (idx < 0) {
        return false;
    }
    if (gov.is_banned[idx] == 1) {
        if (current_time < gov.ban_expires[idx]) {
            return true;
        }
    }
    return false;
}
