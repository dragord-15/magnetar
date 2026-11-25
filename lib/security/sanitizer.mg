// ============================================================================
// Magnetar Security Library: Input Sanitization & Attack Prevention
// File: lib/security/sanitizer.mg
// Prevents SQL Injection, XSS, Command Injection, Path Traversal, and SSRF
// ============================================================================

use "lib/string.mg";

// Helper: safe single-byte read from pointer
fn _byte_at(char* p, int idx) -> int {
    return cast<int>(*(p + idx)) & 255;
}

// ----------------------------------------------------------------------------
// 1. SQL Injection Prevention
// ----------------------------------------------------------------------------

// Escapes special characters for SQL literals: single quotes, backslashes, double quotes
fn sanitize_sql_escape(string input) -> string {
    let p = cast<char*>(input);
    if (p == null) {
        return "";
    }
    let length = str_len(input);
    
    // Allocate space for worst-case doubling of characters + null terminator
    let out = alloc<char>(length * 2 + 1);
    let out_idx = 0;
    
    let i = 0;
    while (i < length) {
        let c = _byte_at(p, i);
        if (c == 39) { // Single quote '
            *(out + out_idx) = cast<char>(92); // \
            out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(39); // '
            out_idx = out_idx + 1;
        } else if (c == 92) { // Backslash \
            *(out + out_idx) = cast<char>(92);
            out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(92);
            out_idx = out_idx + 1;
        } else if (c == 34) { // Double quote "
            *(out + out_idx) = cast<char>(92);
            out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(34);
            out_idx = out_idx + 1;
        } else if (c != 0) { // Strip null bytes
            *(out + out_idx) = cast<char>(c);
            out_idx = out_idx + 1;
        }
        i = i + 1;
    }
    *(out + out_idx) = 0;
    return cast<string>(out);
}

// ----------------------------------------------------------------------------
// 2. Cross-Site Scripting (XSS) Prevention
// ----------------------------------------------------------------------------

// HTML-encodes &, <, >, ", '
fn sanitize_html_escape(string input) -> string {
    let p = cast<char*>(input);
    if (p == null) {
        return "";
    }
    let length = str_len(input);
    
    // Worst case expansion: & -> &amp; (5 chars)
    let out = alloc<char>(length * 6 + 1);
    let out_idx = 0;
    
    let i = 0;
    while (i < length) {
        let c = _byte_at(p, i);
        if (c == 38) { // & -> &amp;
            *(out + out_idx) = cast<char>(38); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(97); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(109); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(112); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(59); out_idx = out_idx + 1;
        } else if (c == 60) { // < -> &lt;
            *(out + out_idx) = cast<char>(38); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(108); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(116); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(59); out_idx = out_idx + 1;
        } else if (c == 62) { // > -> &gt;
            *(out + out_idx) = cast<char>(38); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(103); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(116); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(59); out_idx = out_idx + 1;
        } else if (c == 34) { // " -> &quot;
            *(out + out_idx) = cast<char>(38); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(113); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(117); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(111); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(116); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(59); out_idx = out_idx + 1;
        } else if (c == 39) { // ' -> &#39;
            *(out + out_idx) = cast<char>(38); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(35); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(51); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(57); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(59); out_idx = out_idx + 1;
        } else {
            *(out + out_idx) = cast<char>(c);
            out_idx = out_idx + 1;
        }
        i = i + 1;
    }
    *(out + out_idx) = 0;
    return cast<string>(out);
}

// ----------------------------------------------------------------------------
// 3. Shell Command Injection Prevention
// ----------------------------------------------------------------------------

// Encloses argument in single quotes and safely escapes existing single quotes
fn sanitize_shell_arg(string arg) -> string {
    let p = cast<char*>(arg);
    if (p == null) {
        return "''";
    }
    let length = str_len(arg);
    let out = alloc<char>(length * 4 + 3);
    let out_idx = 0;
    
    *(out + out_idx) = cast<char>(39); // '
    out_idx = out_idx + 1;
    
    let i = 0;
    while (i < length) {
        let c = _byte_at(p, i);
        if (c == 39) { // ' -> '\''
            *(out + out_idx) = cast<char>(39); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(92); out_idx = out_idx + 1; // \
            *(out + out_idx) = cast<char>(39); out_idx = out_idx + 1;
            *(out + out_idx) = cast<char>(39); out_idx = out_idx + 1;
        } else {
            *(out + out_idx) = cast<char>(c);
            out_idx = out_idx + 1;
        }
        i = i + 1;
    }
    
    *(out + out_idx) = cast<char>(39); // '
    out_idx = out_idx + 1;
    *(out + out_idx) = 0;
    return cast<string>(out);
}

// ----------------------------------------------------------------------------
// 4. Path Traversal & LFI Prevention
// ----------------------------------------------------------------------------

// Returns true if path contains directory breakout sequences like ../ or ..\
fn is_path_traversal_attempt(string path) -> bool {
    let p = cast<char*>(path);
    if (p == null) {
        return false;
    }
    let length = str_len(path);
    let i = 0;
    while (i < length - 1) {
        let c1 = _byte_at(p, i);
        let c2 = _byte_at(p, i + 1);
        if (c1 == 46 && c2 == 46) { // ".."
            if (i + 2 < length) {
                let c3 = _byte_at(p, i + 2);
                if (c3 == 47 || c3 == 92) {
                    return true;
                }
            } else {
                return true;
            }
        }
        if (c1 == 0) {
            return true;
        }
        i = i + 1;
    }
    return false;
}

// Sanitizes a relative file name by stripping dangerous directory prefixes
fn sanitize_filename(string filename) -> string {
    let p = cast<char*>(filename);
    if (p == null) {
        return "";
    }
    let length = str_len(filename);
    let out = alloc<char>(length + 1);
    let out_idx = 0;
    
    let i = 0;
    while (i < length) {
        let c = _byte_at(p, i);
        let is_ok = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 46 || c == 45 || c == 95;
        if (is_ok) {
            if (c == 46 && out_idx > 0 && _byte_at(out, out_idx - 1) == 46) {
                // skip consecutive dots
            } else {
                *(out + out_idx) = cast<char>(c);
                out_idx = out_idx + 1;
            }
        }
        i = i + 1;
    }
    *(out + out_idx) = 0;
    return cast<string>(out);
}

// ----------------------------------------------------------------------------
// 5. SSRF Defense & IP Validation
// ----------------------------------------------------------------------------

// Parses an IPv4 octet from string at pos. Returns parsed number, advances pos.
fn _parse_ipv4_octet(char* p, int length, int* pos) -> int {
    let i = *pos;
    if (i >= length) {
        return -1;
    }
    let val = 0;
    let digits = 0;
    while (i < length) {
        let c = _byte_at(p, i);
        if (c >= 48 && c <= 57) {
            val = val * 10 + (c - 48);
            digits = digits + 1;
            if (digits > 3 || val > 255) {
                return -1;
            }
            i = i + 1;
        } else {
            break;
        }
    }
    if (digits == 0) {
        return -1;
    }
    *pos = i;
    return val;
}

// Checks if string is a valid IPv4 address in dot-decimal notation
fn is_valid_ipv4(string ip) -> bool {
    let p = cast<char*>(ip);
    if (p == null) {
        return false;
    }
    let length = str_len(ip);
    let pos = 0;
    
    for (int octet = 0; octet < 4; octet = octet + 1) {
        let val = _parse_ipv4_octet(p, length, &pos);
        if (val < 0 || val > 255) {
            return false;
        }
        if (octet < 3) {
            if (pos >= length) { return false; }
            if (_byte_at(p, pos) != 46) { return false; }
            pos = pos + 1;
        }
    }
    return pos == length;
}

// Checks if IP belongs to private/internal ranges (RFC 1918, loopback, link-local)
// Used to block Server-Side Request Forgery (SSRF) to internal services.
fn is_private_or_loopback_ipv4(string ip) -> bool {
    let p = cast<char*>(ip);
    if (p == null) {
        return false;
    }
    let length = str_len(ip);
    let pos = 0;
    
    let oct0 = _parse_ipv4_octet(p, length, &pos);
    if (pos >= length) { return false; }
    if (_byte_at(p, pos) != 46) { return false; }
    pos = pos + 1;
    
    let oct1 = _parse_ipv4_octet(p, length, &pos);
    if (pos >= length) { return false; }
    if (_byte_at(p, pos) != 46) { return false; }
    pos = pos + 1;
    
    let oct2 = _parse_ipv4_octet(p, length, &pos);
    if (pos >= length) { return false; }
    if (_byte_at(p, pos) != 46) { return false; }
    pos = pos + 1;
    
    let oct3 = _parse_ipv4_octet(p, length, &pos);
    if (oct0 < 0 || oct1 < 0 || oct2 < 0 || oct3 < 0) {
        return false;
    }
    
    // 127.0.0.0/8 (Loopback)
    if (oct0 == 127) { return true; }
    // 10.0.0.0/8 (Private Class A)
    if (oct0 == 10) { return true; }
    // 172.16.0.0/12 (Private Class B: 172.16.x.x - 172.31.x.x)
    if (oct0 == 172 && oct1 >= 16 && oct1 <= 31) { return true; }
    // 192.168.0.0/16 (Private Class C)
    if (oct0 == 192 && oct1 == 168) { return true; }
    // 169.254.0.0/16 (Link-Local & Cloud Metadata 169.254.169.254)
    if (oct0 == 169 && oct1 == 254) { return true; }
    // 0.0.0.0
    if (oct0 == 0) { return true; }
    
    return false;
}
