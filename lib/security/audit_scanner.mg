// ============================================================================
// Magnetar Security Library: Ethical Security Assessment & Audit Scanner
// File: lib/security/audit_scanner.mg
// Defensive attack surface evaluation, port checking & OWASP header scoring
// ============================================================================

use "lib/string.mg";
use "lib/net.mg";

// ----------------------------------------------------------------------------
// 1. Service Port Intelligence & Mapping
// ----------------------------------------------------------------------------

// Returns well-known service name for standard networking ports
fn audit_service_name(int port) -> string {
    if (port == 21) { return "FTP (File Transfer Protocol)"; }
    if (port == 22) { return "SSH (Secure Shell)"; }
    if (port == 23) { return "Telnet (Insecure Plaintext)"; }
    if (port == 25) { return "SMTP (Mail)"; }
    if (port == 53) { return "DNS (Domain Name System)"; }
    if (port == 80) { return "HTTP (Web Plaintext)"; }
    if (port == 110) { return "POP3 (Mail Plaintext)"; }
    if (port == 143) { return "IMAP (Mail Plaintext)"; }
    if (port == 443) { return "HTTPS (Encrypted Web)"; }
    if (port == 3306) { return "MySQL Database"; }
    if (port == 3389) { return "RDP (Remote Desktop)"; }
    if (port == 5432) { return "PostgreSQL Database"; }
    if (port == 6379) { return "Redis In-Memory Store"; }
    if (port == 8080) { return "HTTP-Alt / Proxy"; }
    if (port == 8443) { return "HTTPS-Alt Web Service"; }
    if (port == 27017) { return "MongoDB Database"; }
    return "Custom / Unregistered Service";
}

// Flags legacy plaintext protocols that should be replaced with encrypted equivalents
fn audit_is_insecure_protocol(int port) -> bool {
    // Telnet (23), FTP (21), HTTP (80), POP3 (110), IMAP (143)
    if (port == 21 || port == 23 || port == 80 || port == 110 || port == 143) {
        return true;
    }
    return false;
}

// Performs an authorized socket connectivity audit for a specific IPv4 port
fn audit_check_service_alive(int ip0, int ip1, int ip2, int ip3, int port) -> bool {
    let fd = net_socket_tcp();
    if (fd < 0) {
        return false;
    }
    let ok = net_connect(fd, ip0, ip1, ip2, ip3, port);
    sys_close(fd);
    return ok;
}

// ----------------------------------------------------------------------------
// 2. OWASP Security Header Posture Audit & Scorer
// ----------------------------------------------------------------------------

struct SecurityPostureAudit {
    int total_score;
    string grade;
    bool has_hsts;
    bool has_csp;
    bool has_xfo;
    bool has_xcto;
    bool has_referrer_policy;
}

// Analyzes raw HTTP headers against OWASP Recommended Security Headers
fn audit_evaluate_http_security_posture(string raw_headers) -> SecurityPostureAudit {
    let audit: SecurityPostureAudit;
    audit.total_score = 0;
    audit.has_hsts = false;
    audit.has_csp = false;
    audit.has_xfo = false;
    audit.has_xcto = false;
    audit.has_referrer_policy = false;
    
    let lower = str_to_lower(raw_headers);
    
    // 1. Strict-Transport-Security (HSTS) - 25 points
    if (str_contains(lower, "strict-transport-security:")) {
        audit.has_hsts = true;
        audit.total_score = audit.total_score + 25;
    }
    
    // 2. Content-Security-Policy (CSP) - 25 points
    if (str_contains(lower, "content-security-policy:")) {
        audit.has_csp = true;
        audit.total_score = audit.total_score + 25;
    }
    
    // 3. X-Frame-Options (Clickjacking defense) - 20 points
    if (str_contains(lower, "x-frame-options:")) {
        audit.has_xfo = true;
        audit.total_score = audit.total_score + 20;
    }
    
    // 4. X-Content-Type-Options: nosniff - 15 points
    if (str_contains(lower, "x-content-type-options:")) {
        audit.has_xcto = true;
        audit.total_score = audit.total_score + 15;
    }
    
    // 5. Referrer-Policy - 15 points
    if (str_contains(lower, "referrer-policy:")) {
        audit.has_referrer_policy = true;
        audit.total_score = audit.total_score + 15;
    }
    
    // Assign Letter Grade
    if (audit.total_score >= 85) {
        audit.grade = "A (Strong Defense Posture)";
    } else if (audit.total_score >= 65) {
        audit.grade = "B (Good Posture - Minor Improvements Needed)";
    } else if (audit.total_score >= 40) {
        audit.grade = "C (Weak Posture - Missing Key Protections)";
    } else {
        audit.grade = "F (Failing - Highly Vulnerable to Web Exploits)";
    }
    
    return audit;
}

