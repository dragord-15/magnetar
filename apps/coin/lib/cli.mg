// MGC CLI: builds a JSON-RPC request, sends it over loopback HTTP and prints the body.

use "rpc.mg";
use "../../lib/crypto.mg";
use "../../lib/string.mg";

extern fn os_get_env(string name) -> string;

fn _mgc_cli_arg(char** argv, int index) -> string {
    if (argv == null || index < 0) { return ""; }
    string a = argv[index];
    if (a == null) { return ""; }
    return a;
}

fn _mgc_cli_is_number(string text) -> bool {
    if (text == null) { return false; }
    int n = len(text);
    if (n <= 0) { return false; }
    int i = 0;
    if (*(cast<char*>(text)) == 45) { i = 1; }
    if (i >= n) { return false; }
    while (i < n) {
        if (!is_digit(*(cast<char*>(text) + i))) { return false; }
        i = i + 1;
    }
    return true;
}

fn _mgc_cli_read_cookie(string datadir, string override) -> string {
    if (override != "" && override != null) { return str_clone(override); }
    string dd = datadir;
    if (dd == "" || dd == null) {
        string home = os_get_env("HOME");
        if (home == "" || home == null) { home = "."; }
        dd = str_concat(home, "/.mgc/regtest");
        free(cast<char*>(home));
    }
    string path = mgc_storage_path(dd, ".cookie");
    char* data = null;
    int dlen = 0;
    if (!mgc_storage_read(path, &data, &dlen)) {
        free(cast<char*>(dd));
            return "";
    }
    int start = 0;
    int end = dlen;
    while (start < end && (data[start] == 32 || data[start] == 9 ||
                           data[start] == 10 || data[start] == 13)) { start = start + 1; }
    while (end > start && (data[end - 1] == 32 || data[end - 1] == 9 ||
                           data[end - 1] == 10 || data[end - 1] == 13)) { end = end - 1; }
    string out = str_substr(cast<string>(data), start, end - start);
    free(data);
    if (dd != datadir) { free(cast<char*>(dd)); }
    return out;
}

fn mgc_cli_run(int argc, char** argv) -> int {
    if (argv == null || argc < 2) { return 1; }
    string method = "";
    string datadir = "";
    string cookie_override = "";
    int port = mgc_default_rpc_port(MGC_NETWORK_REGTEST);
    int param_start = -1;
    for (int i = 1; i < argc; i = i + 1) {
        string a = _mgc_cli_arg(argv, i);
        if (a == null || a == "") { continue; }
        if (str_starts_with(a, "--cookie=")) {
            cookie_override = str_substr(a, 9, len(a) - 9);
            continue;
        }
        if (str_starts_with(a, "--datadir=")) {
            datadir = str_substr(a, 10, len(a) - 10);
            continue;
        }
        if (str_starts_with(a, "--port=")) {
            port = str_to_int(str_substr(a, 7, len(a) - 7));
            continue;
        }
        if (str_starts_with(a, "--rpcport=")) {
            port = str_to_int(str_substr(a, 10, len(a) - 10));
            continue;
        }
        if (method == "") {
            method = a;
            param_start = i + 1;
        }
    }
    if (method == "" || port < 1 || port > 65535) { return 1; }

    StringBuilder pb;
    pb.init(128);
    pb.append("[");
    bool first = true;
    if (param_start >= 0) {
        for (int i = param_start; i < argc; i = i + 1) {
            string a = _mgc_cli_arg(argv, i);
            if (a == null || a == "") { continue; }
            if (str_starts_with(a, "--")) { continue; }
            if (!first) { pb.append(","); }
            first = false;
            if (_mgc_cli_is_number(a)) { pb.append(a); }
            else {
                string q = mgc_json_string(a);
                pb.append(q);
                free(cast<char*>(q));
            }
        }
    }
    pb.append("]");
    string params = pb.to_string();
    pb.free_builder();

    StringBuilder jb;
    jb.init(len(params) + 96);
    jb.append("{\"jsonrpc\":\"2.0\",\"method\":");
    string mq = mgc_json_string(method);
    jb.append(mq);
    free(cast<char*>(mq));
    jb.append(",\"params\":");
    jb.append(params);
    jb.append(",\"id\":1}");
    free(cast<char*>(params));
    string body = jb.to_string();
    jb.free_builder();

    string cookie = _mgc_cli_read_cookie(datadir, cookie_override);
    if (cookie == "" || cookie == null) {
        free(cast<char*>(body));
        return 1;
    }
    string userpass = str_concat("rpc:", cookie);
    string b64 = crypto_base64_encode(cast<char*>(userpass), len(userpass));

    StringBuilder hb;
    hb.init(len(body) + 256);
    hb.append("POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: ");
    string num = int_to_str(len(body));
    hb.append(num);
    free(cast<char*>(num));
    hb.append("\r\nAuthorization: Basic ");
    hb.append(b64);
    hb.append("\r\nConnection: close\r\n\r\n");
    hb.append(body);
    string request = hb.to_string();
    hb.free_builder();
    free(cast<char*>(body));
    free(cast<char*>(b64));
    free(cast<char*>(userpass));
    if (cookie != cookie_override) { free(cast<char*>(cookie)); }

    int fd = net_socket_tcp();
    if (fd < 0) {
        free(cast<char*>(request));
        return 1;
    }
    net_set_timeout_ms(fd, 100);
    bool connected = net_connect_localhost(fd, port);
    if (!connected) {
        net_close(fd);
        free(cast<char*>(request));
        return 1;
    }
    int sent = net_send_all_str(fd, request);
    free(cast<char*>(request));
    if (sent <= 0) {
        net_close(fd);
        return 1;
    }

    int max = 1048576;
    char* response = alloc<char>(max + 1);
    if (response == null) {
        net_close(fd);
        return 1;
    }
    int total = 0;
    for (int i = 0; i < 100 && total < max - 1; i = i + 1) {
        int got = net_recv_into(fd, response + total, max - total - 1);
        if (got > 0) { total = total + got; }
        else if (got == 0) { break; }
    }
    *(response + total) = 0;
    net_close(fd);
    if (total <= 0) {
        free(response);
        return 1;
    }
    string text = cast<string>(response);
    int at = str_index_of(text, "\r\n\r\n");
    if (at >= 0) {
        string out = str_substr(text, at + 4, len(text) - at - 4);
        print_str(out);
        free(cast<char*>(out));
    } else {
        print_str(text);
    }
    free(response);
    return 0;
}
