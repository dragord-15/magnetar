// ============================================================================
// Magnetar Security Library: OSINT (Open Source Intelligence)
// File: lib/security/osint.mg
// Passive intelligence, target reconnaissance, URL parsing & header analysis
// ============================================================================

use "lib/string.mg";

// ----------------------------------------------------------------------------
// 1. URL & Target Parsing
// ----------------------------------------------------------------------------

struct ParsedURL {
    string scheme;
    string host;
    int port;
    string path;
}

// Parses URL into scheme, host, port, and path
// Example: "https://example.com:8443/api/v1"
fn osint_parse_url(string url) -> ParsedURL {
    let p: ParsedURL;
    p.scheme = "http";
    p.host = "";
    p.port = 80;
    p.path = "/";
    
    char* s = cast<char*>(url);
    if (s == null) {
        return p;
    }
    let length = str_len(url);
    let idx = 0;
    
    // Check scheme (http:// or https://)
    if (str_starts_with(url, "https://")) {
        p.scheme = "https";
        p.port = 443;
        idx = 8;
    } else if (str_starts_with(url, "http://")) {
        p.scheme = "http";
        p.port = 80;
        idx = 7;
    }
    
    // Extract host and optional :port
    let host_start = idx;
    let host_end = length;
    let slash_idx = -1;
    let colon_idx = -1;
    
    let i = host_start;
    while (i < length) {
        let c = cast<int>(s[i]) & 255;
        if (c == 47) { // '/'
            slash_idx = i;
            break;
        }
        if (c == 58 && colon_idx < 0) { // ':'
            colon_idx = i;
        }
        i = i + 1;
    }
    
    if (slash_idx >= 0) {
        host_end = slash_idx;
        p.path = str_substr(url, slash_idx, length - slash_idx);
    } else {
        host_end = length;
        p.path = "/";
    }
    
    if (colon_idx >= 0 && colon_idx < host_end) {
        p.host = str_substr(url, host_start, colon_idx - host_start);
        let port_str = str_substr(url, colon_idx + 1, host_end - (colon_idx + 1));
        let custom_port = str_to_int(port_str);
        if (custom_port > 0) {
            p.port = custom_port;
        }
    } else {
        p.host = str_substr(url, host_start, host_end - host_start);
    }
    
    return p;
}

// ----------------------------------------------------------------------------
// 2. HTTP Header & Technology Fingerprinting (Passive Recon)
// ----------------------------------------------------------------------------

// Extracts a specific HTTP header value from raw response text (case-insensitive)
fn osint_get_http_header(string raw_headers, string target_header) -> string {
    char* raw_ptr = cast<char*>(raw_headers);
    if (raw_ptr == null) {
        return "";
    }
    let lower_raw = str_to_lower(raw_headers);
    let lower_target = str_concat(str_to_lower(target_header), ":");
    
    let idx = str_index_of(lower_raw, lower_target);
    if (idx < 0) {
        return "";
    }
    
    let val_start = idx + str_len(lower_target);
    let raw_len = str_len(raw_headers);
    
    // Skip spaces after colon
    while (val_start < raw_len) {
        let c = cast<int>(raw_ptr[val_start]) & 255;
        if (c != 32 && c != 9) { // not space, not tab
            break;
        }
        val_start = val_start + 1;
    }
    
    // Find end of line (\r or \n)
    let val_end = val_start;
    while (val_end < raw_len) {
        let c = cast<int>(raw_ptr[val_end]) & 255;
        if (c == 13 || c == 10) { // \r or \n
            break;
        }
        val_end = val_end + 1;
    }
    
    if (val_end > val_start) {
        return str_substr(raw_headers, val_start, val_end - val_start);
    }
    return "";
}

// Fingerprints web server software from Server or X-Powered-By header
fn osint_fingerprint_server(string server_header) -> string {
    if (str_is_empty(server_header)) {
        return "Unknown / Hidden Server";
    }
    let lower = str_to_lower(server_header);
    if (str_contains(lower, "nginx")) { return "Nginx Web Server"; }
    if (str_contains(lower, "apache")) { return "Apache HTTP Server"; }
    if (str_contains(lower, "cloudflare")) { return "Cloudflare Reverse Proxy / CDN"; }
    if (str_contains(lower, "caddy")) { return "Caddy Web Server"; }
    if (str_contains(lower, "microsoft-iis")) { return "Microsoft IIS Server"; }
    if (str_contains(lower, "lighttpd")) { return "Lighttpd Embedded Server"; }
    if (str_contains(lower, "gunicorn") || str_contains(lower, "uvicorn")) { return "Python WSGI/ASGI Server"; }
    if (str_contains(lower, "express")) { return "Node.js Express Framework"; }
    
    return server_header;
}

// ----------------------------------------------------------------------------
// 3. Robots.txt Analysis & Sensitive Endpoint Discovery
// ----------------------------------------------------------------------------

// Checks whether a robots.txt Disallow rule hints at a sensitive administration endpoint
fn osint_is_sensitive_endpoint(string path) -> bool {
    let lower = str_to_lower(path);
    if (str_contains(lower, "admin")) { return true; }
    if (str_contains(lower, "backup") || str_contains(lower, "bak")) { return true; }
    if (str_contains(lower, "config") || str_contains(lower, "conf")) { return true; }
    if (str_contains(lower, "login") || str_contains(lower, "auth")) { return true; }
    if (str_contains(lower, "dashboard")) { return true; }
    if (str_contains(lower, "secret") || str_contains(lower, "private")) { return true; }
    if (str_contains(lower, "internal")) { return true; }
    if (str_contains(lower, "database") || str_contains(lower, "db")) { return true; }
    if (str_contains(lower, "portal")) { return true; }
    return false;
}

// ----------------------------------------------------------------------------
// 4. Domain & Email OSINT Intelligence
// ----------------------------------------------------------------------------

// Extracts domain from an email address (e.g. analyst@defense.gov -> defense.gov)
fn osint_extract_email_domain(string email) -> string {
    let idx = str_index_of(email, "@");
    if (idx < 0) {
        return "";
    }
    let length = str_len(email);
    if (idx + 1 < length) {
        return str_substr(email, idx + 1, length - (idx + 1));
    }
    return "";
}

// Validates SPF (Sender Policy Framework) record syntax to audit email spoofing defense
fn osint_audit_spf_record(string spf_record) -> bool {
    if (str_is_empty(spf_record)) {
        return false;
    }
    let lower = str_to_lower(spf_record);
    if (!str_starts_with(lower, "v=spf1")) {
        return false; // Must declare SPF version 1
    }
    // Must contain policy qualifier (~all, -all, ?all)
    if (str_contains(lower, "-all") || str_contains(lower, "~all") || str_contains(lower, "?all")) {
        return true;
    }
    return false;
}

// Validates DMARC record syntax to audit domain impersonation defense
fn osint_audit_dmarc_record(string dmarc_record) -> bool {
    if (str_is_empty(dmarc_record)) {
        return false;
    }
    let lower = str_to_lower(dmarc_record);
    if (!str_starts_with(lower, "v=dmarc1")) {
        return false; // Must declare DMARC version 1
    }
    // Must specify policy action (p=reject, p=quarantine, p=none)
    if (str_contains(lower, "p=reject") || str_contains(lower, "p=quarantine") || str_contains(lower, "p=none")) {
        return true;
    }
    return false;
}
