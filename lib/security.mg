// ============================================================================
// Magnetar Standard Security Suite (lib/security.mg)
// Complete Defensive Cybersecurity & Systems Protection Library
// ============================================================================

// 1. Memory Hardening & Anti-Forensics (constant-time compare, secure wipe, canaries)
use "lib/security/secure_mem.mg";

// 2. Input Sanitization & Attack Prevention (SQLi, XSS, Command Injection, Path Traversal, SSRF)
use "lib/security/sanitizer.mg";

// 3. Cryptographic Utilities & CSPRNG (Hex/Base64 codecs, UUIDv4, secure tokens, keyed tags)
use "lib/security/crypto_utils.mg";

// 4. Defensive Network Forensics & IDS (IPv4/TCP packet parsing, scan detection: SYN, Xmas, Null, LAND)
use "lib/security/packet_inspect.mg";

// 5. Rate Limiter & Brute-Force Defense (Token bucket / sliding window, automated IP jailing)
use "lib/security/rate_limiter.mg";

// 6. Security Audit & SIEM Logging (CEF - Common Event Format & Syslog incident reporting)
use "lib/security/audit_logger.mg";

// 7. OSINT Intelligence (URL parsing, technology fingerprinting, sensitive endpoints, SPF/DMARC)
use "lib/security/osint.mg";

// 8. Ethical Security Assessment & Audit Scanner (service port auditing, OWASP header posture scorer)
use "lib/security/audit_scanner.mg";
