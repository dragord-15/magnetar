// JSON helper unit tests: escaping, lookups, arrays, envelopes and validation.

use "../lib/json.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;

    string tricky = "a\"b\\c\nd";
    check_string("escape", mgc_json_escape(tricky), "a\\\"b\\\\c\\nd", &failures);
    check_string("json string", mgc_json_string("hi"), "\"hi\"", &failures);

    string json = "{\"name\":\"mgc\",\"ok\":true,\"n\":7,\"params\":[\"a\",1,true],\"msg\":\"line\\nbreak\"}";
    check_bool("json valid", mgc_json_valid(json), true, &failures);
    check_string("get string", mgc_json_get_string(json, "name", "?"), "mgc", &failures);
    check_string("get string fallback", mgc_json_get_string(json, "missing", "fallback"), "fallback", &failures);
    check_int("get int", mgc_json_get_int(json, "n", -1), 7, &failures);
    check_int("get int fallback", mgc_json_get_int(json, "missing", -1), -1, &failures);
    check_bool("get bool", mgc_json_get_bool(json, "ok", false), true, &failures);
    check_bool("get bool fallback", mgc_json_get_bool(json, "missing", true), true, &failures);
    check_string("unescaped newline", mgc_json_get_string(json, "msg", "?"), "line\nbreak", &failures);

    string params = mgc_json_get_params(json);
    check_string("params raw", params, "[\"a\",1,true]", &failures);
    check_int("array count", mgc_json_array_count(params), 3, &failures);
    check_string("array item 0", mgc_json_array_item(params, 0), "a", &failures);
    check_string("array item 1", mgc_json_array_item(params, 1), "1", &failures);
    check_string("array item 2", mgc_json_array_item(params, 2), "true", &failures);
    check_string("array item out", mgc_json_array_item(params, 3), "", &failures);

    check_string("result shape", mgc_json_result(3, "{\"x\":1}"),
                 "{\"jsonrpc\":\"2.0\",\"result\":{\"x\":1},\"id\":3}", &failures);
    check_string("error shape", mgc_json_error(4, -32601, "no \"method\""),
                 "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32601,\"message\":\"no \\\"method\\\"\"},\"id\":4}", &failures);

    check_bool("valid object", mgc_json_valid("{\"a\":[1,2]}"), true, &failures);
    check_bool("invalid brace", mgc_json_valid("{\"a\":1"), false, &failures);
    check_bool("invalid string", mgc_json_valid("{\"a\":\"x}"), false, &failures);
    check_bool("invalid bracket", mgc_json_valid("{\"a\":[1,2}"), false, &failures);

    return test_report("test_json", failures);
}
