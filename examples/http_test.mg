// ============================================================================
// اختبار مكتبات الشبكة والروابط و DNS في لغة Magnetar
// ============================================================================

use "http.mg";
use "dns.mg";
use "url.mg";

extern fn print_str(string s) -> void;

fn main() -> int {
    print_str("=== 1. اختبار تفكيك الرابط (URL Parser) ===\n");
    Url u = url_parse("http://neverssl.com");
    if (u.valid) {
        print_str("النطاق: ");
        print_str(u.host);
        print_str("\nالمسار: ");
        print_str(u.path);
        print_str("\nالاستعلام: ");
        print_str(u.query);
        print_str("\n\n");
    }

    print_str("=== 2. اختبار حل النطاقات (DNS Resolver) ===\n");
    Ipv4Addr ip = dns_resolve("http://neverssl.com");
    if (ip.valid) {
        print_str("تم العثور على IP للموقع http://neverssl.com بنجاح!\n\n");
    } else {
        print_str("فشل الاتصال بخادم DNS.\n\n");
        return 1;
    }

    print_str("=== 3. اختبار طلب HTTP GET ===\n");
    HttpResponse get_resp = http_get("http://neverssl.com");
    if (get_resp.ok) {
        print_str("نجح الطلب (Status 200)! محتوى الرد:\n");
        print_str(get_resp.body);
        print_str("\n\n");
    } else {
        print_str("فشل طلب GET.\n\n");
    }

    print_str("=== 4. اختبار طلب HTTP POST ===\n");
    string json_payload = "{\"language\": \"Magnetar\", \"native\": true}";
    HttpResponse post_resp = http_post("http://neverssl.com", json_payload, "application/json");
    if (post_resp.ok) {
        print_str("نجح إرسال البيانات (POST)! الرد:\n");
        print_str(post_resp.body);
        print_str("\n");
    }

    return 0;
}
