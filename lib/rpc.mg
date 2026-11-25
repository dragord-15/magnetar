// ============================================================================
// Magnetar Standard Library: RPC Helpers (lib/rpc.mg)
// Generic JSON-RPC 2.0 request/response helpers over HTTP.
// For coin-specific RPC server, use coin/lib/rpc.mg.
// ============================================================================

use "lib/json.mg";
use "lib/http.mg";
use "lib/string.mg";

struct RpcClient {
    string endpoint;
    string auth_header;
    int timeout_ms;

    fn init(string url) -> void {
        endpoint = url;
        auth_header = "";
        timeout_ms = 10000;
    }

    fn set_auth(string header) -> void {
        auth_header = header;
    }

    fn set_timeout(int ms) -> void {
        if (ms > 0) { timeout_ms = ms; }
    }

    fn call(string method, string params_json, int id) -> string {
        string req = rpc_build_request(method, params_json, id);
        HttpResponse resp = http_request_ex("POST", endpoint, req, "application/json", auth_header, true, timeout_ms, true);
        free(cast<char*>(req));
        if (resp.error != "") {
            return json_rpc_error(id, -32000, resp.error);
        }
        if (resp.body == null) { return json_rpc_error(id, -32000, "empty response"); }
        return resp.body;
    }
}

fn rpc_build_request(string method, string params_json, int id) -> string {
    string m = json_quote(method);
    string body = str_concat("{\"jsonrpc\":\"2.0\",\"method\":", m);
    string p = str_concat(",\"params\":", params_json);
    string i = str_concat(",\"id\":", int_to_str(id));
    string b1 = str_concat(body, p);
    string b2 = str_concat(b1, i);
    string out = str_concat(b2, "}");
    free(cast<char*>(m));
    free(cast<char*>(p));
    free(cast<char*>(i));
    free(cast<char*>(b1));
    free(cast<char*>(b2));
    return out;
}

fn rpc_get_method(string request_json) -> string {
    return json_get_string(request_json, "method", "");
}

fn rpc_get_id(string request_json) -> int {
    return json_get_int(request_json, "id", 0);
}

fn rpc_get_params(string request_json) -> string {
    return json_get_raw(request_json, "params");
}

fn rpc_ok(int id, string result_json) -> string { return json_rpc_result(id, result_json); }
fn rpc_err(int id, int code, string msg) -> string { return json_rpc_error(id, code, msg); }
