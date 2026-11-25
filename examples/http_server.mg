// ============================================================================
// Magnetar HTTP server demo (incoming requests, routing, JSON, CORS, webhook)
// File: examples/http_server.mg
//
// Build: ./magc examples/http_server.mg -o http_server
// Run:   ./http_server          (listens on 0.0.0.0:8080)
//
// Try:
//   curl -i http://127.0.0.1:8080/
//   curl -i http://127.0.0.1:8080/json
//   curl -i -X POST --data 'hello' http://127.0.0.1:8080/echo
//   curl -i -H 'Authorization: Bearer secret' http://127.0.0.1:8080/api
//   curl -i -X POST -H 'Content-Type: application/json' \
//        --data '{"message":{"text":"ping"}}' http://127.0.0.1:8080/telegram
// ============================================================================

use "lib/http.mg";

extern fn print_str(string s) -> void;

fn webhook_reply(string text) -> string {
    return str_concat("{\"ok\":true,\"reply\":\"", str_concat(http_json_escape(text), "\"}"));
}

fn main() -> int {
    TcpServer server;
    if (!server.start(8080, 32)) {
        print_str("Cannot bind 0.0.0.0:8080\n");
        return 1;
    }
    print_str("Magnetar HTTP server listening on http://0.0.0.0:8080\n");

    while (true) {
        int fd = server.accept_connection();
        if (fd < 0) { continue; }

        HttpRequest req = http_read_request(fd, 5000);
        if (!req.valid) {
            http_send_text(fd, 400, "Bad Request\n");
            net_close(fd);
            continue;
        }

        print_str(req.method);
        print_str(" ");
        print_str(req.path);
        print_str("\n");

        if (req.method == "OPTIONS") {
            http_send_cors_preflight(fd, "*", "", "");
        } else if (req.path == "/") {
            http_send_html(fd, 200, "<h1>Magnetar HTTP</h1><p>Hello from a native server.</p>");
        } else if (req.path == "/health") {
            http_send_json_ex(fd, 200, "{\"status\":\"healthy\"}", "Access-Control-Allow-Origin: *\r\n");
        } else if (req.path == "/json") {
            http_send_json(fd, 200, "{\"ok\":true,\"engine\":\"magnetar\",\"version\":\"3.5\"}");
        } else if (req.path == "/echo") {
            http_send_response_ex(fd, 200, "text/plain; charset=utf-8", req.body_data, req.body_length, "");
        } else if (req.path == "/api") {
            string auth = http_request_header(req, "Authorization");
            if (len(auth) == 0) {
                http_send_json(fd, 401, "{\"error\":\"missing Authorization header\"}");
            } else {
                string body = str_concat("{\"authorized\":true,\"scheme\":\"", str_concat(http_json_escape(auth), "\"}"));
                http_send_json(fd, 200, body);
            }
        } else if (req.path == "/telegram") {
            string text = http_json_get_string(req.body, "text");
            int chat_id = http_json_get_int(req.body, "id");
            if (len(text) == 0) {
                http_send_json(fd, 400, "{\"ok\":false,\"error\":\"no message text\"}");
            } else {
                print_str("Telegram webhook update: ");
                print_str(text);
                print_str("\n");
                http_send_json(fd, 200, webhook_reply(text));
                print_str("chat id: ");
                print(chat_id);
                print_str("\n");
            }
        } else if (req.path == "/redirect") {
            http_send_redirect(fd, "/", 302);
        } else {
            http_send_text(fd, 404, "Not Found\n");
        }

        net_close(fd);
    }
    return 0;
}
