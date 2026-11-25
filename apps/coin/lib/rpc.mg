// MGC JSON-RPC server over loopback HTTP with cookie authentication.

use "node.mg";
use "json.mg";
use "../../lib/net.mg";
use "../../lib/crypto.mg";
use "../../lib/string.mg";

extern fn sys_fcntl(int fd, int cmd, int arg) -> int;

const int MGC_RPC_F_SETFL = 4;
const int MGC_RPC_O_NONBLOCK = 2048;
const int MGC_RPC_RECV_CHUNK = 8192;
const int MGC_RPC_BUF_MAX = 2097152;
const int MGC_RPC_LISTEN_BACKLOG = 16;

struct MgcRpcClient { int fd; char* buf; int buf_len; int buf_cap; }
struct MgcRpcServer {
    int listen_fd;
    int port;
    MgcNode* node;
    int capacity;
 int count; MgcRpcClient* clients; char* cookie; }

fn _mgc_rpc_net_name(int network) -> string {
    if (network == 0) { return "main"; }
    if (network == 1) { return "test"; }
    return "regtest";
}

fn _mgc_rpc_hash_json(char* hash32) -> string {
    if (hash32 == null) { return mgc_json_string(""); }
    string hex = crypto_hex_encode(hash32, 32);
    string out = mgc_json_string(hex);
    free(cast<char*>(hex));
    return out;
}

fn _mgc_rpc_bytes_json(char* data, int len) -> string {
    if (data == null || len <= 0) { return mgc_json_string(""); }
    string hex = crypto_hex_encode(data, len);
    string out = mgc_json_string(hex);
    free(cast<char*>(hex));
    return out;
}

fn _mgc_rpc_addr_from_text(string text, int* ip0, int* ip1, int* ip2, int* ip3, int* port) -> bool {
    if (text == null) { return false; }
    char* p = cast<char*>(text);
    int n = len(text);
    int vals[5];
    int count = 0;
    int i = 0;
    while (i < n && count < 5) {
        if (*(p + i) == 46 || *(p + i) == 58) { i = i + 1; continue; }
        if (*(p + i) < 48 || *(p + i) > 57) { return false; }
        int value = 0;
        int digits = 0;
        while (i < n && *(p + i) >= 48 && *(p + i) <= 57) {
            value = value * 10 + (cast<int>(*(p + i)) - 48);
            if (value > 65535) { return false; }
            digits = digits + 1;
            i = i + 1;
        }
        if (digits <= 0) { return false; }
        vals[count] = value;
        count = count + 1;
        if (i < n && *(p + i) != 46 && *(p + i) != 58) { return false; }
    }
    if (count != 5 || vals[0] > 255 || vals[1] > 255 || vals[2] > 255 || vals[3] > 255) { return false; }
    if (vals[4] < 1) { return false; }
    *ip0 = vals[0];
    *ip1 = vals[1];
    *ip2 = vals[2];
    *ip3 = vals[3];
    *port = vals[4];
    return true;
}

fn mgc_rpc_dispatch(MgcNode* node, string method, string params) -> string {
    if (node == null || method == null || params == null) { return "null"; }
    MgcChain* c = node.cref;
    MgcUtxoSet* u = node.uref;
    MgcMempool* mp = node.mref;
    MgcWallet* w = node.wref;
    if (c == null || u == null || mp == null || w == null) { return "null"; }
    int height = mgc_chain_height(c);
    if (height < 0) { height = 0; }

    if (method == "getblockcount") { return int_to_str(height); }

    if (method == "getbestblockhash") {
        char* h = alloc<char>(32);
        if (h == null) { return "null"; }
        bool ok = mgc_chain_tip_hash(c, h);
        string out = "null";
        if (ok) { out = _mgc_rpc_hash_json(h); }
        free(h);
        return out;
    }

    if (method == "getblockchaininfo") {
        char* h = alloc<char>(32);
        if (h == null) { return "null"; }
        mgc_chain_tip_hash(c, h);
        string hash = _mgc_rpc_hash_json(h);
        free(h);
        StringBuilder sb;
        sb.init(512);
        sb.append("{\"chain\":");
        sb.append(mgc_json_string(_mgc_rpc_net_name(node.network)));
        sb.append(",\"blocks\":");
        sb.append(int_to_str(height));
        sb.append(",\"headers\":");
        sb.append(int_to_str(height));
        sb.append(",\"bestblockhash\":");
        sb.append(hash);
        sb.append(",\"difficulty\":1,\"verificationprogress\":1,\"pruned\":false,\"initialblockdownload\":false}");
        string out = sb.to_string();
        sb.free_builder();
        free(cast<char*>(hash));
        return out;
    }

    if (method == "getblockhash") {
        int wanted = str_to_int(mgc_json_array_item(params, 0));
        int idx = mgc_chain_at_height(c, wanted);
        if (idx < 0) { return "null"; }
        char* h = c.hashes + idx * 32;
        return _mgc_rpc_hash_json(h);
    }

    if (method == "getblock") {
        string hexhash = mgc_json_array_item(params, 0);
        int hlen = 0;
        char* h = crypto_hex_decode(hexhash, &hlen);
        if (h == null || hlen != 32) {
            if (h != null) { free(h); }
            return "null";
        }
        int idx = mgc_chain_find(c, h);
        free(h);
        if (idx < 0) { return "null"; }
        MgcBlock* b = mgc_chain_get(c, idx);
        if (b == null) { return "null"; }
        int blen = 0;
        char* bytes = mgc_block_serialize(b, &blen);
        if (bytes == null || blen <= 0) {
            if (bytes != null) { free(bytes); }
            return "null";
        }
        string out = _mgc_rpc_bytes_json(bytes, blen);
        free(bytes);
        return out;
    }

    if (method == "getrawtransaction") {
        string hexhash = mgc_json_array_item(params, 0);
        int hlen = 0;
        char* h = crypto_hex_decode(hexhash, &hlen);
        if (h == null || hlen != 32) {
            if (h != null) { free(h); }
            return "null";
        }
        MgcTx* found = null;
        int mn = mgc_mempool_count(mp);
        for (int i = 0; i < mn && found == null; i = i + 1) {
            MgcTx* tx = mgc_mempool_get(mp, i);
            char* tid = alloc<char>(32);
            if (tx != null && tid != null) {
                if (mgc_tx_txid(tx, tid) && mgc_equal(tid, h, 32)) { found = tx; }
            }
            if (tid != null) { free(tid); }
        }
        int cn = c.count;
        for (int i = 0; i < cn && found == null; i = i + 1) {
            MgcBlock* b = mgc_chain_get(c, i);
            if (b == null) { continue; }
            for (int j = 0; j < b.tx_count && found == null; j = j + 1) {
                MgcTx* tx = b.txs[j];
                char* tid = alloc<char>(32);
                if (tx != null && tid != null) {
                    if (mgc_tx_txid(tx, tid) && mgc_equal(tid, h, 32)) { found = tx; }
                }
                if (tid != null) { free(tid); }
            }
        }
        free(h);
        if (found == null) { return "null"; }
        int tlen = 0;
        char* bytes = mgc_tx_serialize(found, true, &tlen);
        if (bytes == null || tlen <= 0) {
            if (bytes != null) { free(bytes); }
            return "null";
        }
        string out = _mgc_rpc_bytes_json(bytes, tlen);
        free(bytes);
        return out;
    }

    if (method == "sendrawtransaction") {
        string hex = mgc_json_array_item(params, 0);
        int raw_bytes_len = 0;
        char* raw_bytes = crypto_hex_decode(hex, &raw_bytes_len);
        if (raw_bytes == null || raw_bytes_len <= 0 || raw_bytes_len > 100000) {
            if (raw_bytes != null) { free(raw_bytes); }
            return "null";
        }
        MgcTx* tx = alloc<MgcTx>(1);
        if (tx == null) { free(raw_bytes); return "null"; }
        bool ok = mgc_tx_deserialize(raw_bytes, raw_bytes_len, tx);
        free(raw_bytes);
        int fee = 0;
        if (ok) { ok = mgc_consensus_verify_tx(tx, u, height, node.network, mgc_chain_id(node.network), &fee); }
        if (ok) { ok = mgc_mempool_add(mp, tx); }
        string out = "null";
        if (ok) {
            char* tid = alloc<char>(32);
            if (tid != null && mgc_tx_txid(tx, tid)) {
                mgc_peer_broadcast_inv(node.pref, MGC_INV_TX, tid);
                out = _mgc_rpc_hash_json(tid);
            }
            if (tid != null) { free(tid); }
        }
        mgc_tx_free(tx);
        free(tx);
        return out;
    }

    if (method == "gettxout") {
        string hexhash = mgc_json_array_item(params, 0);
        int index = str_to_int(mgc_json_array_item(params, 1));
        int hlen = 0;
        char* h = crypto_hex_decode(hexhash, &hlen);
        if (h == null || hlen != 32) {
            if (h != null) { free(h); }
            return "null";
        }
        MgcUtxo prev;
        bool ok = mgc_utxo_get(u, h, index, &prev);
        free(h);
        if (!ok) { return "null"; }
        string script_hex = "";
        if (prev.script != null && prev.script_len > 0) {
            script_hex = crypto_hex_encode(prev.script, prev.script_len);
        }
        string script_json = mgc_json_string(script_hex);
        int conf = height - prev.height + 1;
        if (conf < 1) { conf = 1; }
        StringBuilder sb;
        sb.init(256);
        sb.append("{\"bestblock\":");
        char* tip = alloc<char>(32);
        if (tip != null && mgc_chain_tip_hash(c, tip)) { sb.append(_mgc_rpc_hash_json(tip)); }
        else { sb.append("null"); }
        if (tip != null) { free(tip); }
        sb.append(",\"confirmations\":");
        sb.append(int_to_str(conf));
        sb.append(",\"value\":");
        sb.append(int_to_str(prev.value));
        sb.append(",\"scriptPubKey\":{\"hex\":");
        sb.append(script_json);
        sb.append("},\"coinbase\":");
        if (prev.coinbase) { sb.append("true"); } else { sb.append("false"); }
        sb.append("}");
        string out = sb.to_string();
        sb.free_builder();
        mgc_utxo_result_free(&prev);
        free(cast<char*>(script_hex));
        free(cast<char*>(script_json));
        return out;
    }

    if (method == "getbalance") {
        if (w.locked) { return "0"; }
        return int_to_str(mgc_wallet_balance(w, u));
    }

    if (method == "getnewaddress") {
        string addr = mgc_wallet_new_address(w);
        if (addr == "") { return mgc_json_string(""); }
        string out = mgc_json_string(addr);
        free(cast<char*>(addr));
        return out;
    }

    if (method == "sendtoaddress") {
        string addr = mgc_json_array_item(params, 0);
        int amount = str_to_int(mgc_json_array_item(params, 1));
        if (w.locked || amount <= 0) { return "null"; }
        MgcTx tx;
        bool ok = mgc_wallet_create_tx(w, u, addr, node.network, amount, 0, height, &tx);
        if (ok) { ok = mgc_wallet_sign_tx(w, u, node.network, mgc_chain_id(node.network), &tx); }
        int fee = 0;
        if (ok) { ok = mgc_consensus_verify_tx(&tx, u, height, node.network, mgc_chain_id(node.network), &fee); }
        if (ok) { ok = mgc_mempool_add(mp, &tx); }
        string out = "null";
        if (ok) {
            char* tid = alloc<char>(32);
            if (tid != null && mgc_tx_txid(&tx, tid)) {
                mgc_peer_broadcast_inv(node.pref, MGC_INV_TX, tid);
                out = _mgc_rpc_hash_json(tid);
            }
            if (tid != null) { free(tid); }
        }
        mgc_tx_free(&tx);
        return out;
    }

    if (method == "listtransactions") { return "[]"; }

    if (method == "getpeerinfo") {
        StringBuilder sb;
        sb.init(256);
        sb.append("[");
        bool first = true;
        MgcPeerManager* pm = node.pref;
        if (pm != null && pm.peers != null) {
            for (int i = 0; i < pm.capacity; i = i + 1) {
                MgcPeer* p = pm.peers + i * sizeof(MgcPeer);
                if (p != null && p.fd >= 0) {
                    if (!first) { sb.append(","); }
                    first = false;
                    sb.append("{\"id\":");
                    sb.append(int_to_str(i));
                    sb.append(",\"addr\":");
                    string addr = str_concat(int_to_str(p.ip0), ".");
                    addr = str_concat(addr, int_to_str(p.ip1));
                    addr = str_concat(addr, ".");
                    addr = str_concat(addr, int_to_str(p.ip2));
                    addr = str_concat(addr, ".");
                    addr = str_concat(addr, int_to_str(p.ip3));
                    addr = str_concat(addr, ":");
                    addr = str_concat(addr, int_to_str(p.port));
                    sb.append(mgc_json_string(addr));
                    free(cast<char*>(addr));
                    sb.append(",\"height\":");
                    sb.append(int_to_str(p.height));
                    sb.append(",\"inbound\":");
                    if (p.inbound) { sb.append("true"); } else { sb.append("false"); }
                    sb.append("}");
                }
            }
        }
        sb.append("]");
        string out = sb.to_string();
        sb.free_builder();
        return out;
    }

    if (method == "addnode") {
        string addr = mgc_json_array_item(params, 0);
        int ip0 = 0; int ip1 = 0; int ip2 = 0; int ip3 = 0; int port = 0;
        bool ok = _mgc_rpc_addr_from_text(addr, &ip0, &ip1, &ip2, &ip3, &port);
        if (ok) { ok = mgc_node_addnode(node, addr); }
        if (ok) { return "true"; }
        return "false";
    }

    if (method == "getmempoolinfo") {
        StringBuilder sb;
        sb.init(64);
        sb.append("{\"size\":");
        sb.append(int_to_str(mgc_mempool_count(mp)));
        sb.append(",\"bytes\":");
        sb.append(int_to_str(mp.total_bytes));
        sb.append("}");
        string out = sb.to_string();
        sb.free_builder();
        return out;
    }

    if (method == "getmininginfo") {
        StringBuilder sb;
        sb.init(128);
        sb.append("{\"blocks\":");
        sb.append(int_to_str(height));
        sb.append(",\"difficulty\":1,\"networkhashps\":0,\"chain\":");
        sb.append(mgc_json_string(_mgc_rpc_net_name(node.network)));
        sb.append("}");
        string out = sb.to_string();
        sb.free_builder();
        return out;
    }

    if (method == "generate") {
        int wanted = str_to_int(mgc_json_array_item(params, 0));
        if (wanted < 1) { wanted = 1; }
        int start = height;
        int added = mgc_node_generate(node, wanted);
        StringBuilder sb;
        sb.init(128);
        sb.append("[");
        for (int i = 0; i < added; i = i + 1) {
            if (i > 0) { sb.append(","); }
            int idx = mgc_chain_at_height(c, start + i + 1);
            if (idx >= 0) { sb.append(_mgc_rpc_hash_json(c.hashes + idx * 32)); }
            else { sb.append("null"); }
        }
        sb.append("]");
        string out = sb.to_string();
        sb.free_builder();
        return out;
    }

    if (method == "stop") {
        node.stop = true;
        return "true";
    }

    return "null";
}

fn mgc_rpc_server_init(MgcRpcServer* s, int port, string cookie, int capacity) -> bool {
    if (s == null || port < 1 || port > 65535 || cookie == null || capacity < 1 || capacity > 256) { return false; }
    s.listen_fd = -1;
    s.port = port;
    s.node = null;
    s.capacity = capacity;
    s.count = 0;
    s.clients = null;
    s.cookie = null;
    s.clients = alloc<MgcRpcClient>(capacity);
    int clen = len(cookie);
    if (clen > 0 && clen < 256) { s.cookie = alloc<char>(clen + 1); }
    if (s.clients == null || s.cookie == null) {
        mgc_rpc_server_free(s);
        return false;
    }
    mgc_zero(cast<char*>(s.cookie), clen + 1);
    char* cp = cast<char*>(cookie);
    int i = 0;
    while (i < clen) {
        *(s.cookie + i) = *(cp + i);
        i = i + 1;
    }
    *(s.cookie + clen) = 0;
    for (int j = 0; j < capacity; j = j + 1) {
        MgcRpcClient* cl = s.clients + j * sizeof(MgcRpcClient);
        cl.fd = -1;
        cl.buf = null;
        cl.buf_len = 0;
        cl.buf_cap = 0;
    }

    int fd = net_socket_tcp();
    if (fd < 0) {
        mgc_rpc_server_free(s);
        return false;
    }
    char* addr = net_create_loopback_addr(port);
    if (addr == null || sys_bind(fd, addr, 16) != 0 || !net_listen(fd, MGC_RPC_LISTEN_BACKLOG)) {
        if (addr != null) { free(addr); }
        net_close(fd);
        mgc_rpc_server_free(s);
        return false;
    }
    free(addr);
    sys_fcntl(fd, MGC_RPC_F_SETFL, MGC_RPC_O_NONBLOCK);
    s.listen_fd = fd;
    return true;
}

fn _mgc_rpc_close_client(MgcRpcServer* s, int index) -> void {
    if (s == null || s.clients == null || index < 0 || index >= s.capacity) { return; }
    MgcRpcClient* c = s.clients + index * sizeof(MgcRpcClient);
    if (c.fd >= 0) {
        net_close(c.fd);
        c.fd = -1;
        if (s.count > 0) { s.count = s.count - 1; }
    }
    if (c.buf != null) { free(c.buf); }
    c.buf = null;
    c.buf_len = 0;
    c.buf_cap = 0;
}

fn mgc_rpc_server_free(MgcRpcServer* s) -> void {
    if (s == null) { return; }
    if (s.clients != null) {
        for (int i = 0; i < s.capacity; i = i + 1) { _mgc_rpc_close_client(s, i); }
        free(s.clients);
        s.clients = null;
    }
    if (s.listen_fd >= 0) {
        net_close(s.listen_fd);
        s.listen_fd = -1;
    }
    if (s.cookie != null) {
        mgc_zero(s.cookie, 256);
        free(s.cookie);
        s.cookie = null;
    }
    s.capacity = 0;
    s.count = 0;
    s.port = 0;
}

fn _mgc_rpc_send_status(int fd, string status) -> void {
    char* p = cast<char*>(status);
    int n = len(status);
    char* body = alloc<char>(n + 92);
    if (body == null) { return; }
    int k = 0;
    for (int i = 0; i < 9; i = i + 1) { *(body + k) = *(p + i); k = k + 1; }
    char* tail = cast<char*>("\r\nContent-Type: text/plain\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    int tl = len(cast<string>(tail));
    for (int j = 0; j < tl; j = j + 1) { *(body + k) = *(tail + j); k = k + 1; }
    *(body + k) = 0;
    net_send_all_str(fd, cast<string>(body));
    free(body);
}

fn _mgc_rpc_send_json(int fd, string body) -> void {
    StringBuilder sb;
    sb.init(len(body) + 128);
    sb.append("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ");
    string num = int_to_str(len(body));
    sb.append(num);
    free(cast<char*>(num));
    sb.append("\r\nConnection: close\r\n\r\n");
    sb.append(body);
    string out = sb.to_string();
    sb.free_builder();
    net_send_all_str(fd, out);
    free(cast<char*>(out));
}

fn _mgc_rpc_content_length(string req, int header_len) -> int {
    int at = str_index_of(req, "Content-Length:");
    if (at < 0) { at = str_index_of(req, "content-length:"); }
    if (at < 0 || at >= header_len) { return -1; }
    char* p = cast<char*>(req);
    int i = at + 15;
    while (i < header_len && (p[i] == 32 || p[i] == 9)) { i = i + 1; }
    int start = i;
    while (i < header_len && p[i] >= 48 && p[i] <= 57) { i = i + 1; }
    if (i == start) { return -1; }
    string tok = str_substr(req, start, i - start);
    int value = str_to_int(tok);
    free(cast<char*>(tok));
    if (value <= 0) { return -1; }
    return value;
}

fn _mgc_rpc_authorized(string req, int header_len, char* cookie) -> bool {
    if (cookie == null) { return false; }
    string prefix = "Authorization: Basic ";
    int at = str_index_of(req, prefix);
    if (at < 0 || at >= header_len) { return false; }
    char* p = cast<char*>(req);
    int start = at + len(prefix);
    int end = start;
    while (end < header_len && p[end] != 13 && p[end] != 10) { end = end + 1; }
    string cred = str_substr(req, start, end - start);
    string userpass = str_concat("rpc:", cast<string>(cookie));
    string expected = crypto_base64_encode(cast<char*>(userpass), len(userpass));
    bool ok = str_equals(cred, expected);
    free(cast<char*>(cred));
    free(cast<char*>(userpass));
    free(cast<char*>(expected));
    return ok;
}

fn _mgc_rpc_service_client(MgcRpcServer* s, MgcNode* node, int index, char* tmp) -> bool {
    if (s == null || s.clients == null || index < 0 || index >= s.capacity) { return false; }
    MgcRpcClient* c = s.clients + index * sizeof(MgcRpcClient);
    if (c.fd < 0) { return false; }
    int r = net_recv_into(c.fd, tmp, MGC_RPC_RECV_CHUNK);
    if (r == 0) {
        _mgc_rpc_close_client(s, index);
        return false;
    }
    if (r < 0) { return false; }
    int need = c.buf_len + r;
    if (need > MGC_RPC_BUF_MAX - 1) {
        _mgc_rpc_send_status(c.fd, "413 Request Entity Too Large");
        _mgc_rpc_close_client(s, index);
        return false;
    }
    if (c.buf == null || c.buf_cap <= need) {
        int cap = 8193;
        while (cap <= need && cap < MGC_RPC_BUF_MAX) { cap = cap * 2; }
        if (cap > MGC_RPC_BUF_MAX) { cap = MGC_RPC_BUF_MAX; }
        char* fresh = alloc<char>(cap);
        if (fresh == null) {
            _mgc_rpc_close_client(s, index);
            return false;
        }
        if (c.buf_len > 0) { mgc_copy(fresh, c.buf, c.buf_len); }
        if (c.buf != null) { free(c.buf); }
        c.buf = fresh;
        c.buf_cap = cap;
    }
    mgc_copy(c.buf + c.buf_len, tmp, r);
    c.buf_len = need;
    *(c.buf + c.buf_len) = 0;

    string req = cast<string>(c.buf);
    int seat = str_index_of(req, "\r\n\r\n");
    if (seat < 0) { return false; }
    int clen = _mgc_rpc_content_length(req, seat);
    if (clen <= 0 || clen > 1048576 || seat + 4 + clen > c.buf_len) { return false; }
    if (!_mgc_rpc_authorized(req, seat, s.cookie)) {
        _mgc_rpc_send_status(c.fd, "401 Unauthorized");
        _mgc_rpc_close_client(s, index);
        return true;
    }
    string body = str_substr(req, seat + 4, clen);
    if (body == "") {
        _mgc_rpc_send_status(c.fd, "400 Bad Request");
        _mgc_rpc_close_client(s, index);
        return true;
    }
    string method = mgc_json_get_string(body, "method", "");
    int id = mgc_json_get_int(body, "id", 0);
    string params = mgc_json_get_params(body);
    string result = mgc_rpc_dispatch(node, method, params);
    string env = mgc_json_result(id, result);
    _mgc_rpc_send_json(c.fd, env);
    free(cast<char*>(env));
    free(cast<char*>(body));
    _mgc_rpc_close_client(s, index);
    return true;
}

fn _mgc_rpc_accept_ready(MgcRpcServer* s) -> void {
    int accepted = 0;
    while (accepted < s.capacity) {
        int fd = net_accept(s.listen_fd);
        if (fd < 0) { return; }
        int slot = -1;
        for (int i = 0; i < s.capacity; i = i + 1) {
            MgcRpcClient* c = s.clients + i * sizeof(MgcRpcClient);
            if (c.fd < 0) { slot = i; break; }
        }
        if (slot < 0) {
            net_close(fd);
            return;
        }
        net_set_timeout_ms(fd, 20);
        MgcRpcClient* cl = s.clients + slot * sizeof(MgcRpcClient);
        cl.fd = fd;
        cl.buf = alloc<char>(8193);
        if (cl.buf == null) {
            net_close(fd);
            cl.fd = -1;
            return;
        }
        mgc_zero(cl.buf, 8193);
        cl.buf_len = 0;
        cl.buf_cap = 8193;
        s.count = s.count + 1;
        accepted = accepted + 1;
    }
}

fn mgc_rpc_pump(MgcRpcServer* s, MgcNode* node, int timeout_ms) -> int {
    if (s == null || s.clients == null || s.listen_fd < 0) { return 0; }
    if (s.node == null) { s.node = node; }
    int nfds = s.capacity + 1;
    char* fds = alloc<char>(nfds * 8);
    char* tmp = alloc<char>(MGC_RPC_RECV_CHUNK);
    if (fds == null || tmp == null) {
        if (fds != null) { free(fds); }
        if (tmp != null) { free(tmp); }
        return 0;
    }
    mgc_zero(fds, nfds * 8);
    endian_write_u32_le(fds, 0, s.listen_fd);
    endian_write_u16_le(fds, 4, 1);
    for (int i = 0; i < s.capacity; i = i + 1) {
        MgcRpcClient* c = s.clients + i * sizeof(MgcRpcClient);
        int fd = -1;
        if (c.fd >= 0) { fd = c.fd; }
        int off = (i + 1) * 8;
        endian_write_u32_le(fds, off, fd);
        endian_write_u16_le(fds, off + 4, 1);
    }
    int ready = sys_poll(fds, nfds, timeout_ms);
    int handled = 0;
    if (ready > 0) {
        int listen_events = endian_read_u16_le(fds, 6);
        if (listen_events != 0) {
            _mgc_rpc_accept_ready(s);
            handled = handled + 1;
        }
        for (int i = 0; i < s.capacity; i = i + 1) {
            MgcRpcClient* c = s.clients + i * sizeof(MgcRpcClient);
            if (c.fd < 0) { continue; }
            int ev = endian_read_u16_le(fds, (i + 1) * 8 + 6);
            if (ev != 0) {
                if (_mgc_rpc_service_client(s, node, i, tmp)) { handled = handled + 1; }
            }
        }
    }
    free(fds);
    free(tmp);
    return handled;
}
