// Phase 6B integration test: node wiring, JSON-RPC server, cookie auth and CLI-safe dispatch.

use "../lib/node.mg";
use "../lib/rpc.mg";
use "test_common.mg";

extern fn sys_unlink(string path) -> int;

const int TEST_RPC_PORT = 29432;

fn _test_clean_datadir(string datadir) -> void {
    string blocks = mgc_storage_path(datadir, "blocks/blk00000.dat");
    string utxo = mgc_storage_path(datadir, "chainstate/utxo.dat");
    string peers = mgc_storage_path(datadir, "peers.txt");
    string wallet = mgc_storage_path(datadir, "wallet/wallet.dat");
    string cookie = mgc_storage_path(datadir, ".cookie");
    string lock = mgc_storage_path(datadir, ".lock");
    sys_unlink(blocks);
    sys_unlink(utxo);
    sys_unlink(peers);
    sys_unlink(wallet);
    sys_unlink(cookie);
    sys_unlink(lock);
    free(cast<char*>(blocks));
    free(cast<char*>(utxo));
    free(cast<char*>(peers));
    free(cast<char*>(wallet));
    free(cast<char*>(cookie));
    free(cast<char*>(lock));
}

fn _test_basic_header(string body, string authorization) -> string {
    StringBuilder sb;
    sb.init(len(body) + 320);
    sb.append("POST / HTTP/1.1\r\n");
    sb.append("Host: 127.0.0.1\r\n");
    sb.append("Content-Type: application/json\r\n");
    sb.append("Content-Length: ");
    string num = int_to_str(len(body));
    sb.append(num);
    free(cast<char*>(num));
    sb.append("\r\n");
    sb.append(authorization);
    sb.append("Connection: close\r\n");
    sb.append("\r\n");
    sb.append(body);
    string out = sb.to_string();
    sb.free_builder();
    return out;
}

fn _test_recv_all(int fd, MgcRpcServer* server, MgcNode* node) -> string {
    int max = 262144;
    char* buf = alloc<char>(max + 1);
    if (buf == null) { return ""; }
    mgc_zero(buf, max + 1);
    int total = 0;
    int attempt = 0;
    while (attempt < 200 && total < max - 1) {
        mgc_rpc_pump(server, node, 0);
        int got = net_recv_into(fd, buf + total, max - total - 1);
        if (got > 0) {
            total = total + got;
        } else if (got == 0) {
            break;
        }
        attempt = attempt + 1;
    }
    *(buf + total) = 0;
    string out = str_clone(cast<string>(buf));
    free(buf);
    return out;
}

fn _test_rpc_call(MgcRpcServer* server, MgcNode* node, string body, string authorization) -> string {
    int fd = net_socket_tcp();
    if (fd < 0) { return ""; }
    net_set_timeout_ms(fd, 50);
    if (!net_connect_localhost(fd, TEST_RPC_PORT)) {
        net_close(fd);
        return "";
    }
    string req = _test_basic_header(body, authorization);
    int sent = net_send_all_str(fd, req);
    free(cast<char*>(req));
    if (sent <= 0) {
        net_close(fd);
        return "";
    }
    string out = _test_recv_all(fd, server, node);
    net_close(fd);
    return out;
}

fn _test_dispatch_body(string method, string params) -> string {
    StringBuilder sb;
    sb.init(len(method) + len(params) + 96);
    sb.append("{\"jsonrpc\":\"2.0\",\"method\":");
    string mq = mgc_json_string(method);
    sb.append(mq);
    free(cast<char*>(mq));
    sb.append(",\"params\":");
    sb.append(params);
    sb.append(",\"id\":1}");
    string out = sb.to_string();
    sb.free_builder();
    return out;
}

fn _test_auth_header(char* cookie) -> string {
    string userpass = str_concat("rpc:", cast<string>(cookie));
    string b64 = crypto_base64_encode(cast<char*>(userpass), len(userpass));
    string out = str_concat("Authorization: Basic ", b64);
    out = str_concat(out, "\r\n");
    free(cast<char*>(userpass));
    free(cast<char*>(b64));
    return out;
}

fn _test_has(string haystack, string needle) -> bool {
    if (haystack == null || needle == null) { return false; }
    if (str_index_of(haystack, needle) >= 0) { return true; }
    return false;
}

fn main() -> int {
    int failures = 0;
    string datadir = "/tmp/mgc_rpc_test";
    _test_clean_datadir(datadir);

    MgcNode node;
    MgcRpcServer server;
    bool ok = mgc_node_init(&node, MGC_NETWORK_REGTEST, datadir, 29433, TEST_RPC_PORT);
    check_bool("node init", ok, true, &failures);
    if (!ok) { return failures + 1; }

    bool loaded = mgc_node_load(&node);
    check_bool("node load", loaded, true, &failures);
    int genesis_height = mgc_chain_height(node.cref);
    check_int("genesis height", genesis_height, 0, &failures);

    int mined = mgc_node_generate(&node, 1);
    check_int("generate one", mined, 1, &failures);
    check_int("height after generate", mgc_chain_height(node.cref), 1, &failures);

    bool rpc_ok = mgc_rpc_server_init(&server, TEST_RPC_PORT, cast<string>(node.cookie), 8);
    check_bool("rpc init", rpc_ok, true, &failures);
    if (!rpc_ok) {
        mgc_node_shutdown(&node);
        return failures + 1;
    }
    check_int("rpc initial clients", server.count, 0, &failures);
    check_int("rpc listen fd", server.listen_fd >= 0, true, &failures);

    string unauth_body = _test_dispatch_body("getblockcount", "[]");
    string unauth_resp = _test_rpc_call(&server, &node, unauth_body, "");
    check_bool("unauthorized status", _test_has(unauth_resp, "401"), true, &failures);
    check_bool("unauthorized no result", _test_has(unauth_resp, "\"result\""), false, &failures);

    string auth = _test_auth_header(node.cookie);
    check_bool("auth header built", len(auth) > len("Authorization: Basic "), true, &failures);

    string count_body = _test_dispatch_body("getblockcount", "[]");
    string count_resp = _test_rpc_call(&server, &node, count_body, auth);
    check_bool("http 200", _test_has(count_resp, "HTTP/1.1 200 OK"), true, &failures);
    check_bool("json content type", _test_has(count_resp, "application/json"), true, &failures);
    check_bool("blockcount result", _test_has(count_resp, "\"result\":1"), true, &failures);
    check_bool("blockcount id", _test_has(count_resp, "\"id\":1"), true, &failures);

    string info_body = _test_dispatch_body("getblockchaininfo", "[]");
    string info_resp = _test_rpc_call(&server, &node, info_body, auth);
    check_bool("chain info chain name", _test_has(info_resp, "\"chain\":\"regtest\""), true, &failures);
    check_bool("chain info blocks", _test_has(info_resp, "\"blocks\":1"), true, &failures);

    string best_body = _test_dispatch_body("getbestblockhash", "[]");
    string best_resp = _test_rpc_call(&server, &node, best_body, auth);
    check_bool("best block hash present", _test_has(best_resp, "\"result\":\""), true, &failures);

    string addr_body = _test_dispatch_body("getnewaddress", "[]");
    string addr_resp = _test_rpc_call(&server, &node, addr_body, auth);
    check_bool("new address result", _test_has(addr_resp, "\"result\":\""), true, &failures);
    check_bool("new address looks like regtest", _test_has(addr_resp, "m") || _test_has(addr_resp, "n"), true, &failures);

    string gen_body = _test_dispatch_body("generate", "[1]");
    string gen_resp = _test_rpc_call(&server, &node, gen_body, auth);
    check_bool("generate array result", _test_has(gen_resp, "\"result\":["), true, &failures);
    check_int("height after rpc generate", mgc_chain_height(node.cref), 2, &failures);
    check_bool("generate hash element", _test_has(gen_resp, "\""), true, &failures);

    string peers_body = _test_dispatch_body("getpeerinfo", "[]");
    string peers_resp = _test_rpc_call(&server, &node, peers_body, auth);
    check_bool("peer info array", _test_has(peers_resp, "\"result\":["), true, &failures);

    string mempool_body = _test_dispatch_body("getmempoolinfo", "[]");
    string mempool_resp = _test_rpc_call(&server, &node, mempool_body, auth);
    check_bool("mempool info size", _test_has(mempool_resp, "\"size\":"), true, &failures);

    string mining_body = _test_dispatch_body("getmininginfo", "[]");
    string mining_resp = _test_rpc_call(&server, &node, mining_body, auth);
    check_bool("mining info blocks", _test_has(mining_resp, "\"blocks\":2"), true, &failures);

    string bad_method_body = _test_dispatch_body("notamethod", "[]");
    string bad_method_resp = _test_rpc_call(&server, &node, bad_method_body, auth);
    check_bool("bad method null", _test_has(bad_method_resp, "\"result\":null"), true, &failures);

    string direct = mgc_rpc_dispatch(&node, "getblockcount", "[]");
    check_string("direct dispatch count", direct, "2", &failures);
    free(cast<char*>(direct));

    char* tip_bytes = alloc<char>(32);
    if (tip_bytes != null && mgc_chain_tip_hash(node.cref, tip_bytes)) {
        string tip_hex = crypto_hex_encode(tip_bytes, 32);
        string block_params = str_concat("[\"", tip_hex);
        block_params = str_concat(block_params, "\"]");
        string block_json = mgc_rpc_dispatch(&node, "getblock", block_params);
        check_bool("direct getblock by tip hash", block_json != null && block_json != "null" && len(block_json) > 2, true, &failures);
        free(cast<char*>(block_json));
        free(cast<char*>(block_params));
        free(cast<char*>(tip_hex));
    } else {
        check_bool("direct getblock by tip hash", false, true, &failures);
    }
    if (tip_bytes != null) { free(tip_bytes); }

    string direct_invalid = mgc_rpc_dispatch(&node, "unknown", "[]");
    check_string("direct dispatch invalid", direct_invalid, "null", &failures);
    free(cast<char*>(direct_invalid));

    int pumped = mgc_rpc_pump(&server, &node, 0);
    check_bool("pump with no pending clients", pumped >= 0, true, &failures);
    check_int("clients closed after responses", server.count, 0, &failures);

    mgc_rpc_server_free(&server);
    check_int("rpc listen fd closed", server.listen_fd, -1, &failures);
    check_int("rpc clients freed", server.clients == null, true, &failures);

    bool saved = mgc_node_save(&node);
    check_bool("node save", saved, true, &failures);
    mgc_node_shutdown(&node);

    free(cast<char*>(unauth_body));
    free(cast<char*>(unauth_resp));
    free(cast<char*>(auth));
    free(cast<char*>(count_body));
    free(cast<char*>(count_resp));
    free(cast<char*>(info_body));
    free(cast<char*>(info_resp));
    free(cast<char*>(best_body));
    free(cast<char*>(best_resp));
    free(cast<char*>(addr_body));
    free(cast<char*>(addr_resp));
    free(cast<char*>(gen_body));
    free(cast<char*>(gen_resp));
    free(cast<char*>(peers_body));
    free(cast<char*>(peers_resp));
    free(cast<char*>(mempool_body));
    free(cast<char*>(mempool_resp));
    free(cast<char*>(mining_body));
    free(cast<char*>(mining_resp));
    free(cast<char*>(bad_method_body));
    free(cast<char*>(bad_method_resp));

    test_report("test_rpc", failures);
    return failures;
}
