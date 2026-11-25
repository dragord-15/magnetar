// ============================================================================
// Magnetar Security Library: Security Audit & SIEM / CEF Logging
// File: lib/security/audit_logger.mg
// Formats security events in Common Event Format (CEF) and Syslog style
// ============================================================================

use "lib/string.mg";

// Severity Levels
const int SEV_INFO       = 1;
const int SEV_WARNING    = 3;
const int SEV_SUSPICIOUS = 5;
const int SEV_ALERT      = 7;
const int SEV_CRITICAL   = 10;

// Standard Security Event Identifiers
fn evt_auth_failure() -> string { return "AUTH_FAILURE"; }
fn evt_rate_limit() -> string { return "RATE_LIMIT_EXCEEDED"; }
fn evt_port_scan() -> string { return "PORT_SCAN_DETECTED"; }
fn evt_sqli_attempt() -> string { return "SQLI_ATTEMPT"; }
fn evt_xss_attempt() -> string { return "XSS_ATTEMPT"; }
fn evt_path_traversal() -> string { return "PATH_TRAVERSAL_ATTEMPT"; }
fn evt_canary_corrupted() -> string { return "MEMORY_TAMPERING_CANARY"; }

// Formats a security event into Common Event Format (CEF):
// CEF:Version|Device Vendor|Device Product|Device Version|Signature ID|Name|Severity|Extension
fn audit_format_cef(string event_id, string event_name, int severity, string src_ip, string details) -> string {
    let out = str_concat("CEF:0|Magnetar|DefensiveEngine|1.0|", event_id);
    out = str_concat(out, "|");
    out = str_concat(out, event_name);
    out = str_concat(out, "|");
    out = str_concat(out, int_to_str(severity));
    out = str_concat(out, "|src=");
    out = str_concat(out, src_ip);
    out = str_concat(out, " msg=");
    out = str_concat(out, details);
    return out;
}

// Directly prints an audited security incident in standardized CEF format
fn audit_log_incident(string event_id, int severity, string src_ip, string details) -> void {
    let line = audit_format_cef(event_id, event_id, severity, src_ip, details);
    print_str(line);
    print("\n");
}
