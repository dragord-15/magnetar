// ============================================================================
// Advanced HTTP/URL toolkit demo (offline)
// File: examples/http_advanced.mg
//
// Shows sessions, cookies, auth headers, HMAC signing, JWT HS256,
// multipart/form-data and URL helpers without touching the network.
//
// Build: ./magc examples/http_advanced.mg -o http_advanced
// Run:   ./http_advanced
// ============================================================================

use "lib/http.mg";
use "lib/url.mg";

extern fn print_str(string s) -> void;

fn main() -> int {
    print_str("=== URL toolkit ===\n");
    string target = "HTTP://API.Example.COM:80/v1/../v2/users?limit=10#top";
    print_str("normalize : "); print_str(url_normalize(target)); print_str("\n");
    print_str("origin    : "); print_str(url_origin(target)); print_str("\n");
    print_str("base      : "); print_str(url_base_domain("api.example.co.uk")); print_str("\n");
    print_str("subdomain : "); print_str(url_host_subdomain("api.example.co.uk")); print_str("\n");
    print_str("add query : "); print_str(url_add_query("https://x.com/search", "q", "magnetar lang")); print_str("\n");
    print_str("remove q  : "); print_str(url_remove_query("https://x.com/p?a=1&b=2", "a")); print_str("\n");
    print_str("data URL  : "); print_str(url_data_decode("data:text/plain;base64,TWFnbmV0YXI=")); print_str("\n");
    print_str("private?  : "); print(url_is_private_host("10.20.30.40")); print_str("\n\n");

    print_str("=== Session / cookies ===\n");
    HttpClient session = http_client_new("https://api.example.com/v1");
    session.timeout_ms = 20000;
    session.retries = 2;
    http_client_set_header(session, "Accept", "application/json");
    http_client_set_header(session, "X-Client", "magnetar-bot");
    http_client_set_bearer(session, "YOUR_API_TOKEN");
    session.cookies = http_cookie_header_from_set_cookie(session.cookies, "sid=abc123; Path=/; HttpOnly");
    session.cookies = http_cookie_header_from_set_cookie(session.cookies, "theme=dark; Path=/");
    print_str("cookies   : "); print_str(session.cookies); print_str("\n");
    print_str("sid       : "); print_str(http_client_cookie(session, "sid")); print_str("\n");
    print_str("base URL  : "); print_str(session.base_url); print_str("\n\n");

    print_str("=== Auth / signing / JWT ===\n");
    print_str("Basic     : "); print_str(http_basic_auth_value("admin", "secret")); print_str("\n");
    print_str("Bearer    : "); print_str(http_bearer_auth_value("YOUR_TOKEN")); print_str("\n");
    print_str("HMAC      : "); print_str(http_hmac_sha256_hex("key", "message")); print_str("\n");
    string token = http_jwt_encode_hs256("{\"sub\":\"42\",\"role\":\"admin\"}", "jwt-secret");
    print_str("JWT       : "); print_str(token); print_str("\n");
    print_str("JWT body  : "); print_str(http_jwt_payload_hs256(token)); print_str("\n");
    print_str("JWT valid?: "); print(http_jwt_verify_hs256(token, "jwt-secret")); print_str("\n\n");

    print_str("=== multipart/form-data ===\n");
    HttpMultipart form = http_multipart_new();
    http_multipart_add_field(form, "username", "torvalds");
    http_multipart_add_field(form, "note", "hello from Magnetar");
    http_multipart_add_file(form, "avatar", "avatar.png", "image/png", cast<char*>("PNGDATA"), 7);
    http_multipart_finish(form);
    print_str("content-type: "); print_str(http_multipart_content_type(form)); print_str("\n");
    print_str("body length : "); print(http_multipart_length(form)); print_str("\n");
    http_multipart_free(form);

    print_str("\n=== Live request pattern (uncomment when needed) ===\n");
    print_str("// HttpResponse r = http_client_get(session, \"/users/42\");\n");
    print_str("// if (r.ok) { print_str(r.body); }\n");
    return 0;
}
