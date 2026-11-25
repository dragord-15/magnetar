// lib/mde_ipc.mg - MDE protocol helpers (JSON line messages)

use "lib/json.mg";
use "lib/string.mg";

fn _mde_itoa(int n) -> string {
    if (n == 0) { return "0"; }
    int neg = 0;
    int v = n;
    if (v < 0) { neg = 1; v = 0 - v; }
    char* tmp = alloc<char>(24);
    int i = 0;
    while (v > 0) {
        *(tmp + i) = cast<char>(48 + (v - (v / 10) * 10));
        v = v / 10;
        i = i + 1;
    }
    char* out = alloc<char>(i + neg + 1);
    int k = 0;
    if (neg == 1) { *(out + k) = 45; k = k + 1; }
    int j = i - 1;
    while (j >= 0) { *(out + k) = *(tmp + j); k = k + 1; j = j - 1; }
    *(out + k) = 0;
    free(tmp);
    return cast<string>(out);
}

fn _mde_int_json(int n) -> string {
    // plain JSON number as string fragment
    return _mde_itoa(n);
}

fn mde_res_ok(int id, string result_json) -> string {
    string s = "{\"t\":\"res\",\"id\":";
    s = str_concat(s, _mde_int_json(id));
    s = str_concat(s, ",\"ok\":true,\"result\":");
    s = str_concat(s, result_json);
    s = str_concat(s, "}");
    return s;
}

fn mde_res_err(int id, string code, string msg) -> string {
    string s = "{\"t\":\"res\",\"id\":";
    s = str_concat(s, _mde_int_json(id));
    s = str_concat(s, ",\"ok\":false,\"error\":{\"code\":");
    s = str_concat(s, json_quote(code));
    s = str_concat(s, ",\"message\":");
    s = str_concat(s, json_quote(msg));
    s = str_concat(s, "}}");
    return s;
}

fn mde_evt(string event, string params_json) -> string {
    string s = "{\"t\":\"evt\",\"event\":";
    s = str_concat(s, json_quote(event));
    s = str_concat(s, ",\"params\":");
    s = str_concat(s, params_json);
    s = str_concat(s, "}");
    return s;
}

fn mde_req(int id, string method, string params_json) -> string {
    string s = "{\"t\":\"req\",\"id\":";
    s = str_concat(s, _mde_int_json(id));
    s = str_concat(s, ",\"method\":");
    s = str_concat(s, json_quote(method));
    s = str_concat(s, ",\"params\":");
    s = str_concat(s, params_json);
    s = str_concat(s, "}");
    return s;
}
