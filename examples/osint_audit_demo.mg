// ============================================================================
// Magnetar OSINT & Ethical Security Assessment Demonstration
// File: examples/osint_audit_demo.mg
// Demonstrates open-source intelligence gathering and security posture auditing
// ============================================================================

use "lib/security.mg";

fn main() -> void {
    print("==================================================================\n");
    print("   Magnetar OSINT & Ethical Security Assessment Demonstration    \n");
    print("==================================================================\n\n");

    // -------------------------------------------------------------
    // 1. Target Reconnaissance & URL Parsing
    // -------------------------------------------------------------
    print("[1] Target URL Reconnaissance:\n");
    string target = "https://portal.bank.internal:8443/auth/v2/login?flow=oauth";
    let url_info = osint_parse_url(target);
    print("  -> Analyzed Target: "); print_str(target); print("\n");
    print("     * Scheme: "); print_str(url_info.scheme); print("\n");
    print("     * Host: "); print_str(url_info.host); print("\n");
    print("     * Port: ", url_info.port, "\n");
    print("     * Path: "); print_str(url_info.path); print("\n\n");

    // -------------------------------------------------------------
    // 2. Passive Web Technology Fingerprinting
    // -------------------------------------------------------------
    print("[2] Passive Web Server & Stack Fingerprinting:\n");
    string sample_headers = "HTTP/1.1 200 OK\r\nServer: cloudflare\r\nX-Powered-By: Express\r\nContent-Type: text/html\r\n\r\n";
    let srv = osint_get_http_header(sample_headers, "Server");
    let powered_by = osint_get_http_header(sample_headers, "X-Powered-By");
    print("  -> Raw Server Header: "); print_str(srv); print("\n");
    print("  -> Fingerprint: "); print_str(osint_fingerprint_server(srv)); print("\n");
    print("  -> Backend Framework: "); print_str(osint_fingerprint_server(powered_by)); print("\n\n");

    // -------------------------------------------------------------
    // 3. Robots.txt Analysis & Sensitive Path Discovery
    // -------------------------------------------------------------
    print("[3] Public Robots.txt Endpoint Reconnaissance:\n");
    string rule1 = "/public/docs";
    string rule2 = "/admin/internal/database_backup.sql";
    print("  -> Endpoint '"); print_str(rule1); print("': Sensitive? ", osint_is_sensitive_endpoint(rule1), "\n");
    print("  -> Endpoint '"); print_str(rule2); print("': Sensitive? ", osint_is_sensitive_endpoint(rule2), " [FLAGGED FOR AUDIT]\n\n");

    // -------------------------------------------------------------
    // 4. Domain & Email Anti-Spoofing Audit (SPF / DMARC)
    // -------------------------------------------------------------
    print("[4] Organization Email Spoofing Defense Audit:\n");
    string email = "ciso@fintech-corp.com";
    let domain = osint_extract_email_domain(email);
    print("  -> Target Domain from Email: "); print_str(domain); print("\n");

    let spf = "v=spf1 include:_spf.google.com ip4:192.0.2.1 ~all";
    let dmarc = "v=DMARC1; p=reject; sp=reject; pct=100; rua=mailto:dmarc-reports@fintech-corp.com";
    print("  -> Auditing SPF Record Syntax: ", osint_audit_spf_record(spf), " (Configured Properly)\n");
    print("  -> Auditing DMARC Strict Policy (p=reject): ", osint_audit_dmarc_record(dmarc), " (Protected Against Spoofing)\n\n");

    // -------------------------------------------------------------
    // 5. Network Service Port Assessment & Protocol Hardening
    // -------------------------------------------------------------
    print("[5] Service Port Assessment & Attack Surface Analysis:\n");
    int ports[4] = {22, 23, 80, 443};
    for (int i = 0; i < 4; i = i + 1) {
        let p = ports[i];
        let name = audit_service_name(p);
        let insecure = audit_is_insecure_protocol(p);
        print("  -> Port ", p, " ["); print_str(name); print("] -> ");
        if (insecure) {
            print("WARNING: Insecure Plaintext! Upgrade to TLS/SSH\n");
        } else {
            print("OK: Encrypted / Secure Protocol\n");
        }
    }
    print("\n");

    // -------------------------------------------------------------
    // 6. OWASP HTTP Security Header Posture Scoring
    // -------------------------------------------------------------
    print("[6] OWASP Defensive HTTP Headers Posture Scorer:\n");
    string audited_response = "HTTP/1.1 200 OK\r\nStrict-Transport-Security: max-age=31536000\r\nContent-Security-Policy: default-src 'self'\r\nX-Frame-Options: SAMEORIGIN\r\nX-Content-Type-Options: nosniff\r\n\r\n";
    let posture = audit_evaluate_http_security_posture(audited_response);
    print("  -> Posture Score: ", posture.total_score, "/100\n");
    print("  -> Security Grade: "); print_str(posture.grade); print("\n");
    print("  -> Protections Present: HSTS=", posture.has_hsts, " CSP=", posture.has_csp, " X-Frame-Options=", posture.has_xfo, "\n");

    print("\n==================================================================\n");
    print("   OSINT & Security Assessment Suite Completed Successfully!      \n");
    print("==================================================================\n");
}

