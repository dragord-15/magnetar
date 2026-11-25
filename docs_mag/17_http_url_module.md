# 17 — مكتبتا HTTP و URL (الاتصال بالمواقع واستقبال الطلبات)

> **الفكرة باختصار**
> - `lib/http.mg`: عميل HTTP/1.1 + خادم HTTP، مع HTTPS حقيقي عبر جسر OpenSSL.
> - `lib/url.mg`: محلّل URL متوافق مع RFC 3986 + ترميز وفك ترميز + استعلامات + `data:` URLs.
> - `lib/crypto.mg`: طبقات التشفير (Base64/Hex/Base32، MD5/SHA-1/SHA-256، HMAC، PBKDF2، AES، ChaCha20، RC4، XOR).
> - `lib/tls.mg`: HTTPS عبر تشغيل `openssl s_client` كناقل TLS.
> - تصلح لبناء بوت Telegram (Polling أو Webhook) وأدوات OSINT/أمن سيبراني مثل Sherlock.

---

## 1) الاستيراد والبناء

```c
use "lib/http.mg";
use "lib/url.mg";
```

```bash
./magc examples/http_advanced.mg -o http_advanced
./http_advanced
```

> [!IMPORTANT]
> `print()` مع السلاسل النصية يطبع **عنوان المؤشر** وليس النص. استخدم `print_str(s)` للنصوص
> و`print(n)` للأعداد. هذا سلوك اللغة الحالي.

---

## 2) مكتبة `lib/url.mg`

### 2.1 البنية `Url`

```c
struct Url {
    string scheme;    // "https"
    string userinfo;  // "user:pass"
    string username;
    string password;
    string host;      // "example.com" أو IPv6 بدون أقواس
    int port;         // المنفذ الفعلي (صريح أو افتراضي)
    string path;      // "/api/v1"
    string query;     // "a=1&b=2" بدون '?'
    string fragment;  // "section" بدون '#'
    bool valid;
    bool has_port;
    bool is_ipv6;
    bool secure;
};
```

```c
Url u = url_parse("https://user:pass@api.example.co.uk:8443/v1/users?limit=10#top");
if (u.valid) {
    print_str(u.scheme);   // https
    print_str(u.host);     // api.example.co.uk
    print(u.port);         // 8443
    print_str(u.path);     // /v1/users
    print_str(u.query);    // limit=10
    print_str(u.fragment); // top
}
```

### 2.2 التحقق والبروتوكولات

```c
url_is_valid(s)
url_has_scheme(s)
url_is_absolute(s)
url_is_relative(s)
url_is_http(s)
url_is_https(s)
url_is_secure_scheme(scheme)
url_scheme_known(scheme)
url_default_port(scheme)
url_scheme_from_port(port)
```

البروتوكولات المدعومة في التحليل والمنافذ الافتراضية:

| العائلة | الأمثلة |
|---|---|
| Web | `http`, `https`, `ws`, `wss` |
| نقل/طرفية | `ftp`, `ftps`, `sftp`, `ssh`, `scp`, `telnet`, `tftp`, `gopher` |
| بريد | `smtp`, `smtps`, `imap`, `imaps`, `pop3`, `pop3s` |
| قواعد بيانات | `postgres`, `postgresql`, `mysql`, `mongodb`, `mongodb+srv`, `redis`, `rediss` |
| رسائل | `mqtt`, `mqtts`, `amqp`, `amqps` |
| دليل | `ldap`, `ldaps`, `dns` |
| أخرى | `file`, `data`, `socks4`, `socks4a`, `socks5`, `socks5h`, `tor` |

### 2.3 الترميز وفك الترميز

```c
url_encode(s)
url_encode_path(s)
url_encode_query_component(s)
url_encode_form_component(s)      // المسافة تصبح '+'
url_encode_form("a=1&b=hello world")
url_decode(s)                     // '+' => مسافة
url_decode_strict(s)              // '+' تبقى كما هي
```

### 2.4 الاستعلامات (Query String)

```c
url_query_get(query, "key")
url_query_has(query, "key")
url_query_build(params)
url_add_query(url, "q", "mag")      // يضيف أو يستبدل
url_append_query(url, "tag", "x")   // يضيف دائماً (تكرار مسموح)
url_remove_query(url, "debug")      // يحذف كل قيم المفتاح
url_merge_query(url, "a=1&b=2")
```

> [!WARNING]
> يوجد قيد حالي في المترجم عند **إرجاع بنية كبيرة تحوي مصفوفات نصوص** من دالة.
> استعمل `url_query_get()` أو `url_query_parse_into()`، ولا تعتمد على:
> ```c
> QueryParams q = url_query_parse(query); // قد يتلف العنصر الثاني وما بعده
> ```
> الطريقة الآمنة:
> ```c
> QueryParams q;
> url_query_parse_into("a=1&b=2", q);
> print_str(q.keys[0]);   // a
> print_str(q.values[1]); // 2
> ```

### 2.5 التركيب والتطبيع

```c
url_normalize(s)       // lowercase للـ scheme/host + حذف المنفذ الافتراضي + إزالة ./ و ../
url_build(u)
url_origin(s)          // scheme://host[:port] دون مسار أو مستخدم
url_authority(u)
url_request_target(u)  // path?query
url_join(base, rel)    // حل مرجع نسبي (RFC 3986)
url_join_path(base, "child")
url_with_query(url, "a=1")
url_with_path(url, "/new")
url_without_query(url)
url_without_fragment(url)
url_without_userinfo(url)
url_strip_fragment(url)
url_strip_auth(url)
url_strip_credentials(url)
url_with_scheme(url, "https")
url_to_https(url)
url_to_http(url)
url_set_fragment(url, "top")
url_same_origin(a, b)
```

```c
print_str(url_normalize("HTTP://API.Example.COM:80/v1/../v2/users?limit=10"));
// http://api.example.com/v2/users?limit=10

print_str(url_join("https://x.com/a/b/", "../c"));
// https://x.com/a/c
```

### 2.6 النطاقات والمسارات

```c
url_host_only(url)
url_host_of(url)
url_scheme_of(url)
url_path_of(url)
url_query_of(url)
url_fragment_of(url)
url_port_of(url)
url_userinfo_of(url)

url_base_domain("api.example.co.uk")    // example.co.uk
url_host_tld("api.example.co.uk")       // uk
url_host_subdomain("api.example.co.uk") // api

url_last_path_segment(url)
url_path_segment(url, 1)
url_path_segment_count(url)

url_is_ipv4_host(host)
url_is_ipv6_host(host)
url_is_localhost(host)
url_is_private_host(host)        // 10/8, 127/8, 169.254/16, 172.16/12, 192.168/16 ...
url_is_safe_public_url(url)      // يرفض private/localhost والبروتوكولات غير http(s)
```

`url_is_private_host` و`url_is_safe_public_url` مفيدان للحماية من **SSRF** قبل إرسال طلب.

### 2.7 روابط `data:`

```c
DataUrl d = url_data_parse("data:text/plain;charset=utf-8;base64,SGVsbG8=");
print_str(d.media_type); // text/plain
print_str(d.charset);    // utf-8
print(d.base64);         // 1

print_str(url_data_decode("data:text/plain;base64,TWFnbmV0YXI=")); // Magnetar

int n = 0;
char* bytes = url_data_decode_raw("data:application/octet-stream;base64,AAEC", &n);
// bytes ثنائية آمنة، و n هو الطول
```

---

## 3) مكتبة `lib/http.mg` — العميل

### 3.1 بنية الاستجابة `HttpResponse`

```c
struct HttpResponse {
    int status_code;
    string status_text;
    string http_version;
    string headers;       // سطور الهيدر فقط
    string raw_headers;   // سطر الحالة + الهيدرات
    string body;          // كـ C string (يتوقف عند NUL)
    char* body_data;      // ثنائي آمن
    int body_length;      // الطول الحقيقي
    bool ok;              // 2xx
    bool chunked;
    string content_type;
    string location;
    string final_url;
    int redirects;
    string error;
};
```

للبيانات الثنائية استخدم دائماً `body_data` + `body_length`، وليس `body`.

### 3.2 الطلبات السريعة

```c
HttpResponse http_get(url)
HttpResponse http_get_insecure(url)
HttpResponse http_get_timeout(url, ms)
HttpResponse http_get_with_headers(url, headers)

HttpResponse http_post(url, body, content_type)
HttpResponse http_post_json(url, json)
HttpResponse http_post_form(url, form_data)
HttpResponse http_post_with_headers(url, body, content_type, headers)

HttpResponse http_put(url, body, content_type)
HttpResponse http_delete(url)
HttpResponse http_head(url)

HttpResponse http_request(method, url, body, content_type)
HttpResponse http_request_ex(method, url, body, content_type, headers,
                             follow_redirects, timeout_ms, verify_tls)
HttpResponse http_request_bytes_ex(method, url, body_data, body_length,
                                   content_type, headers,
                                   follow_redirects, timeout_ms, verify_tls)
```

```c
HttpResponse r = http_get("https://api.github.com/users/torvalds");
if (r.error != "") {
    print_str("error: "); print_str(r.error); print_str("\n");
} else {
    print("status: "); print(r.status_code); print_str("\n");
    print_str("name: "); print_str(http_json_get_string(r.body, "name")); print_str("\n");
    print_str("type: "); print_str(http_header_value(r.headers, "Content-Type")); print_str("\n");
}
```

### 3.3 الجلسة `HttpClient` (شبيهة بـ `requests.Session`)

```c
HttpClient http_client_new(base_url)

http_client_set_header(c, name, value)
http_client_remove_header(c, name)
http_client_set_basic_auth(c, username, password)
http_client_set_bearer(c, token)
http_client_clear_cookies(c)
http_client_cookie(c, name)

http_client_get(c, url)
http_client_head(c, url)
http_client_delete(c, url)
http_client_post(c, url, body, content_type)
http_client_post_json(c, url, json)
http_client_post_form(c, url, form_data)
http_client_put(c, url, body, content_type)
http_client_request(c, method, url, body, content_type)
http_client_request_bytes(c, method, url, body_data, body_length, content_type)
```

حقول قابلة للضبط:

```c
c.base_url          // "https://api.example.com/v1"
c.user_agent        // "MagnetarHTTP/1.1"
c.timeout_ms        // 15000
c.verify_tls        // true
c.follow_redirects  // true
c.max_redirects     // 8
c.retries           // 1
c.retry_delay_ms    // 400
c.cookies           // "sid=abc; theme=dark"
```

```c
HttpClient c = http_client_new("https://api.example.com/v1");
http_client_set_header(c, "Accept", "application/json");
http_client_set_bearer(c, "YOUR_TOKEN");
c.timeout_ms = 20000;
c.retries = 2;

HttpResponse r = http_client_get(c, "/users/42");
if (r.ok) { print_str(r.body); }
```

> [!NOTE]
> كوكيز الجلسة تُدار كنص `Cookie:` بسيط (اسم/قيمة). لعزل صارم حسب النطاق والمسار،
> استخدم `HttpClient` مستقلاً لكل مضيف أو أدر الكوكيز بنفسك.

### 3.4 الكوكيز

```c
http_cookie_header_get(jar, "sid")
http_cookie_header_set(jar, "sid", "abc")
http_cookie_header_remove(jar, "sid")
http_cookie_header_from_set_cookie(jar, "sid=abc; Path=/; HttpOnly")
http_cookie_header_from_response(jar, response)
```

`http_cookie_header_from_response` يحلّل كل سطور `Set-Cookie` ويحدّث الـ jar،
ويحذف الكوكي عند `Max-Age <= 0`.

### 3.5 المصادقة والتوقيع و JWT

```c
http_basic_auth_value("user", "pass")
http_basic_auth_header("user", "pass")
http_bearer_auth_value("token")
http_bearer_auth_header("token")
http_hmac_sha256_hex(secret, message)
http_hmac_signature_header(secret, message)

string jwt = http_jwt_encode_hs256("{\"sub\":\"42\"}", "secret");
string payload = http_jwt_payload_hs256(jwt);
bool valid = http_jwt_verify_hs256(jwt, "secret");
```

`http_jwt_verify_hs256` يستعمل مقارنة ثابتة الزمن عبر `http_const_time_equal`.

### 3.6 Multipart والرفع والتنزيل

```c
HttpMultipart m = http_multipart_new();

http_multipart_add_field(m, "username", "torvalds");
http_multipart_add_field(m, "note", "hello");
http_multipart_add_file(m, "avatar", "avatar.png", "image/png", data, data_len);
http_multipart_finish(m);

print_str(http_multipart_content_type(m));
print(http_multipart_length(m));
char* body = http_multipart_body(m);
HttpResponse r = http_post_multipart(url, m, headers);
http_multipart_free(m);
```

```c
HttpResponse r1 = http_upload_file("https://example.com/upload", "file", "/tmp/a.png");
HttpResponse r2 = http_upload_file_ex(url, "file", "/tmp/a.png", "Authorization: Bearer x\r\n");

bool ok1 = http_download("https://example.com/image.png", "/tmp/image.png");
bool ok2 = http_download_ex(url, "/tmp/file.bin", headers, 60000);
bool ok3 = http_save_response(response, "/tmp/body.bin");
```

### 3.7 أدوات الفحص و OSINT

```c
http_probe(url)                    // كود الحالة أو -1
http_probe_ex(url, headers, ms)
http_body_contains(body, needle)   // بحث غير حساس للحالة
http_html_title(html)              // محتوى <title>
http_status_class(status)          // 200 -> 2
http_is_success(status)
http_is_redirect(status)
http_is_client_error(status)
http_is_server_error(status)
http_json_get_string(json, key)
http_json_get_int(json, key)
http_json_escape(text)
```

هذه الدوال مناسبة لأدوات مثل Sherlock: أرسل طلباً إلى رابط الملف الشخصي، افحص
`status_code`، ثم اطبع النتيجة.

---

## 4) مكتبة `lib/http.mg` — الخادم

### 4.1 القراءة والكتابة

```c
TcpServer server;
server.start(8080, 32);

int fd = server.accept_connection();
HttpRequest req = http_read_request(fd, 5000);

if (req.valid) {
    print_str(req.method); print_str(" "); print_str(req.path); print_str("\n");
    print_str(http_request_header(req, "User-Agent"));
    print_str(http_request_query(req, "id"));
    print_str(http_request_cookie(req, "sid"));
}

http_send_text(fd, 200, "hello");
http_send_html(fd, 200, "<h1>Hi</h1>");
http_send_json(fd, 200, "{\"ok\":true}");
http_send_response(fd, 200, "text/plain", body, body_length);
net_close(fd);
```

### 4.2 بنية الطلب `HttpRequest`

```c
struct HttpRequest {
    string method;
    string target;
    string version;
    string path;
    string query;
    string headers;
    string body;
    char* body_data;
    int body_length;
    int content_length;
    bool valid;
    string error;
};
```

### 4.3 أدوات إضافية

```c
http_listen(port)
http_request_header(req, name)
http_request_query(req, key)
http_request_cookie(req, name)
http_request_json_string(req, key)
http_request_json_int(req, key)
http_request_form(req, key)

http_send_text_ex(fd, status, text, headers)
http_send_json_ex(fd, status, json, headers)
http_send_response_ex(fd, status, content_type, body, len, headers)
http_send_redirect(fd, "/login", 302)
http_send_file(fd, "/var/www/index.html", "text/html")
http_send_cors_preflight(fd, "*", "", "")
http_status_text(code)
```

### 4.4 خادم كامل مع Webhook لتلغرام

```c
use "lib/http.mg";

fn main() -> int {
    TcpServer server;
    if (!server.start(8080, 32)) { return 1; }

    while (true) {
        int fd = server.accept_connection();
        HttpRequest req = http_read_request(fd, 5000);
        if (!req.valid) { net_close(fd); continue; }

        if (req.method == "OPTIONS") {
            http_send_cors_preflight(fd, "*", "", "");
        } else if (req.path == "/telegram") {
            string text = http_json_get_string(req.body, "text");
            int chat_id = http_json_get_int(req.body, "chat_id");
            print_str("update: "); print_str(text); print_str("\n");
            string reply = "{\"ok\":true}";
            http_send_json(fd, 200, reply);
        } else {
            http_send_text(fd, 404, "Not Found");
        }
        net_close(fd);
    }
    return 0;
}
```

مثال جاهز كامل: `examples/http_server.mg`.

```bash
./magc examples/http_server.mg -o http_server
./http_server
curl -i http://127.0.0.1:8080/json
curl -i -X POST --data 'hello' http://127.0.0.1:8080/echo
```

### 4.5 WebSocket (RFC 6455)

```c
bool is_ws = http_websocket_is_upgrade(req);
string accept = http_websocket_accept(client_key);
http_websocket_handshake_response(fd, client_key); // يرسل 101 Switching Protocols
```

---

## 5) HTTPS و TLS

`https://` يعمل عبر `lib/tls.mg` الذي يشغّل:

```text
برنامج Magnetar  <--pipe-->  openssl s_client  <--TCP/TLS-->  السيرفر
```

- يتطلب وجود `openssl` في `/usr/bin/openssl` أو `/bin/openssl` أو `/usr/local/bin/openssl`.
- `verify_tls = true` يفعّل التحقق من الشهادة.
- للاختبار فقط: `http_get_insecure(url)` أو `verify_tls = false`.
- `tls_available()` للتحقق من توفر OpenSSL.

> [!NOTE]
> الخادم الحالي (`TcpServer` + `http_read_request`) يعمل بـ HTTP عادي. لتقديم HTTPS
> للخادم استخدم وكيلاً عكسياً (nginx/caddy) أو أضف جسر `openssl s_server` لاحقاً.

---

## 6) طبقات التشفير المتاحة (`lib/crypto.mg`)

| الفئة | الدوال |
|---|---|
| ترميز | `crypto_hex_encode/decode`, `crypto_base64_encode/decode`, `crypto_base64url_encode/decode`, `crypto_base32_encode` |
| كلاسيكي | `crypto_rot13`, `crypto_caesar`, `crypto_xor_raw/hex`, `crypto_rc4_raw/hex` |
| تجزئة | `crypto_md5_hex`, `crypto_sha1_hex`, `crypto_sha256_hex/bytes` |
| MAC/KDF | `crypto_hmac_sha256_hex/raw`, `crypto_pbkdf2_sha256_hex/raw` |
| تشفير متماثل | `crypto_aes_block_encrypt/decrypt`, AES-ECB/CBC/CTR, `crypto_chacha20_xor_raw/hex` |
| تكامل | `crypto_crc32`, `crypto_crc32_hex`, `crypto_fnv1a32`, `crypto_fnv1a_hex` |
| عشوائية | `crypto_rng_bytes`, `crypto_rng_hex` |

```c
string b64 = crypto_base64_encode(data, data_len);
string sha = crypto_sha256_hex("hello");
string mac = crypto_hmac_sha256_hex("key", "message");
string aes = crypto_aes_cbc_encrypt_hex("plaintext", key_hex, iv_hex);
string plain = crypto_aes_cbc_decrypt_hex(aes, key_hex, iv_hex);
string key = crypto_pbkdf2_sha256_hex("password", "salt", 100000, 32);
```

> [!WARNING]
> هذه التطبيقات تعليمية/أساسية ومكتوبة بلغة Magnetar. للإنتاج الحرج استخدم مكتبات
> تشفير مدققة أو OpenSSL مباشرة.

---

## 7) بوت Telegram

المكتبة `lib/telegram.mg` مبنية فوق `lib/http.mg`:

```c
tg_init(token);
tg_get_me();
tg_send_message(chat_id, "Hello");
tg_send_message_md(chat_id, "*bold*");
tg_send_photo(chat_id, url, caption);
tg_poll_updates();       // Long Polling
tg_answer_callback(id, text, alert);
```

### نمط Polling

```c
use "lib/telegram.mg";

fn main() -> int {
    tg_init("YOUR_BOT_TOKEN");
    while (true) {
        TelegramUpdateBatch batch = tg_poll_updates();
        for (int i = 0; i < batch.count; i = i + 1) {
            TelegramUpdate item = batch.items[i];
            string text = item.text;
            if (text == "/start") {
                tg_send_message(item.chat_id, "Welcome!");
            } else if (len(text) > 0) {
                tg_send_message(item.chat_id, text);
            }
        }
    }
    return 0;
}
```

### نمط Webhook

1. شغّل خادم HTTP على منفذ عام (أو عبر نفق مثل ngrok/cloudflared).
2. اضبط الويب هوك عبر Telegram:

```text
https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://your-domain/telegram
```

3. استقبل `POST /telegram` في خادم Magnetar (انظر `examples/http_server.mg`)،
   ثم استخرج `message.text` و`message.chat.id` وأرسل الرد عبر `tg_send_message`.

> [!CAUTION]
> لا تضع توكن البوت في مستودع عام. استعمله من متغير بيئة أو ملف إعداد غير متتبع.

---

## 8) مثال Sherlock (OSINT)

الملف: `examples/sherlock.mg`

```bash
./magc examples/sherlock.mg -o sherlock
./sherlock
```

الفكرة:

```c
int status = http_probe_ex(profile_url, "User-Agent: Mozilla/5.0\r\n", 8000);
if (status == 200) {
    // الحساب موجود
} else if (status == 404) {
    // غير موجود
} else if (status == 403 || status == 429) {
    // محجوب أو تجاوزت الحد
}
time_sleep_ms(350); // احترام الموقع
```

> [!NOTE]
> بعض المواقع ترجع 200 لصفحات "غير موجود" أو لصفحات حماية. افحص محتوى الصفحة
> أيضاً باستعمال `http_body_contains` و`http_html_title`، ولا تعتبر الكود وحده دليلاً قاطعاً.

روابط البحث العكسي عن الصور (تظهر في المثال):

- Google Lens: `https://lens.google.com/uploadbyurl?url=<ENCODED_URL>`
- Yandex: `https://yandex.com/images/search?rpt=imageview&url=<ENCODED_URL>`
- Bing Visual Search: `https://www.bing.com/images/search?view=detailv2&iss=sbi&q=imgurl:<ENCODED_URL>`
- TinEye: `https://tineye.com/search?url=<ENCODED_URL>`

---

## 9) ملاحظات وحدود مهمة

1. **الكلمة `raw` محجوزة** — لا تستعملها كاسم متغير (`string raw` خطأ ترجمة).
2. **الكلمة `base`** قد تسبب مشاكل في بعض السياقات — استعمل `base_domain` أو اسماً آخر.
3. **لا تضع بنية داخل بنية** (`struct A { B b; }`) — قد تسبب Segfault في المترجم الحالي.
   استعمل حقولاً مسطّحة أو مؤشراً.
4. **مصفوفة بنيات داخل بنية** (`Item items[4]`) قد تنهار أيضاً — استعمل مصفوفات متوازية
   من `string`/`int` كما في `examples/sherlock.mg`.
5. **لا تستخدم محليين كبيرين من `QueryParams`** في نفس الدالة؛ استعمل واحداً + `parse_into`.
6. **لا فحص حدود** — تجنّب الفهارس الخارجة عن النطاق.
7. **الخادم HTTP/1.1 مع `Connection: close`** — لا keep-alive حالياً.
8. **التحقق من TLS** يعتمد على OpenSSL المثبّت في النظام.
9. **لا يوجد gzip/deflate تلقائي** — الطلبات ترسل `Accept-Encoding: identity`.
10. **إعادة التوجيه** مدعومة حتى 8 قفزات، مع تحويل POST إلى GET عند 303 و301/302.

---

## 10) مرجع سريع

| الحاجة | الدالة |
|---|---|
| طلب GET | `http_get(url)` |
| طلب POST JSON | `http_post_json(url, json)` |
| جلسة | `http_client_new(base)` ثم `http_client_get(c, path)` |
| كوكي | `http_cookie_header_from_response(jar, r)` |
| Basic Auth | `http_basic_auth_header(user, pass)` |
| Bearer | `http_bearer_auth_header(token)` |
| JWT | `http_jwt_encode_hs256(payload, secret)` |
| رفع ملف | `http_upload_file(url, field, path)` |
| تنزيل ملف | `http_download(url, path)` |
| فحص حالة | `http_probe(url)` |
| خادم | `TcpServer` + `http_read_request` + `http_send_json` |
| Webhook | `http_json_get_string(req.body, "text")` |
| إصلاح رابط | `url_normalize(url)` |
| إضافة استعلام | `url_add_query(url, key, value)` |
| حماية SSRF | `url_is_safe_public_url(url)` |

---

> [!CAUTION]
> استخدم هذه المكتبات فقط لاختبار الأنظمة التي تملكها أو لديك إذن كتابي باختبارها.
> احترم شروط الاستخدام و`robots.txt` والحدود القانونية في بلدك.
