// Magnetar Coin — single-threaded TCP peer manager.
// v0 simplification: the `headers` payload carries 32-byte block hashes, not full 80-byte headers.

use "p2p.mg";
use "addrman.mg";
use "chain.mg";
use "mempool.mg";
use "params.mg";
use "../../lib/net.mg";
use "../../lib/crypto.mg";

extern fn sys_poll(char* fds, int nfds, int timeout) -> int;
extern fn sys_fcntl(int fd, int cmd, int arg) -> int;

const int MGC_PEER_POLLIN_FLAG = 1;
const int MGC_PEER_POLLERR_FLAG = 8;
const int MGC_PEER_POLLHUP_FLAG = 16;
const int MGC_PEER_RECV_CHUNK = 8192;
const int MGC_PEER_BUF_MAX = 8388608;
const int MGC_PEER_MAX_HEADERS = 2000;
const int MGC_PEER_F_SETFL = 4;
const int MGC_PEER_O_NONBLOCK = 2048;

struct MgcPeer {
    int fd; int ip0; int ip1; int ip2; int ip3; int port; bool inbound;
    bool connected; bool verified; int nonce; int height; int ban_score; int last_activity;
    char* buf; int buf_len; int buf_cap;
}

struct MgcPeerManager {
    int network; int magic; int chain_id; int capacity; int count;
    MgcPeer* peers; int listen_fd; int listen_port; int self_nonce;
    MgcAddrMan* addrman; MgcChain* chain; MgcMempool* mempool;
}

fn _mgc_peer_at(MgcPeerManager* pm, int index) -> MgcPeer* {
    if (pm == null || pm.peers == null || index < 0 || index >= pm.capacity) { return null; }
    return pm.peers + index * sizeof(MgcPeer);
}

fn _mgc_peer_find_free(MgcPeerManager* pm) -> int {
    if (pm == null) { return -1; }
    for (int i = 0; i < pm.capacity; i = i + 1) {
        MgcPeer* p = _mgc_peer_at(pm, i);
        if (p != null && p.fd < 0) { return i; }
    }
    return -1;
}

fn mgc_peer_disconnect(MgcPeerManager* pm, int index) -> void {
    MgcPeer* p = _mgc_peer_at(pm, index);
    if (p == null) { return; }
    if (p.fd >= 0) {
        net_close(p.fd);
        p.fd = -1;
        if (pm != null && pm.count > 0) { pm.count = pm.count - 1; }
    }
    if (p.buf != null) { free(p.buf); }
    p.buf = null;
    p.buf_len = 0;
    p.buf_cap = 0;
    p.ip0 = 0; p.ip1 = 0; p.ip2 = 0; p.ip3 = 0; p.port = 0;
    p.inbound = false;
    p.connected = false;
    p.verified = false;
    p.nonce = 0;
    p.height = 0;
    p.ban_score = 0;
    p.last_activity = 0;
}

fn _mgc_peer_ban(MgcPeerManager* pm, int index, int points) -> void {
    MgcPeer* p = _mgc_peer_at(pm, index);
    if (p == null) { return; }
    p.ban_score = p.ban_score + points;
    if (p.ban_score >= 100) { mgc_peer_disconnect(pm, index); }
}

fn mgc_peer_manager_init(MgcPeerManager* pm, int network, int listen_port, int capacity,
                         MgcAddrMan* addrman, MgcChain* chain, MgcMempool* mempool) -> bool {
    if (pm == null || capacity <= 0 || listen_port <= 0 || listen_port > 65535) { return false; }
    pm.network = network;
    pm.magic = mgc_p2p_magic(network);
    pm.chain_id = mgc_chain_id(network);
    pm.capacity = capacity;
    pm.count = 0;
    pm.peers = null;
    pm.listen_fd = -1;
    pm.listen_port = listen_port;
    pm.self_nonce = 0;
    pm.addrman = addrman;
    pm.chain = chain;
    pm.mempool = mempool;

    pm.peers = alloc<MgcPeer>(capacity);
    if (pm.peers == null) { return false; }
    for (int i = 0; i < capacity; i = i + 1) {
        MgcPeer* p = _mgc_peer_at(pm, i);
        p.fd = -1;
        p.ip0 = 0; p.ip1 = 0; p.ip2 = 0; p.ip3 = 0; p.port = 0;
        p.inbound = false;
        p.connected = false;
        p.verified = false;
        p.nonce = 0;
        p.height = 0;
        p.ban_score = 0;
        p.last_activity = 0;
        p.buf = null;
        p.buf_len = 0;
        p.buf_cap = 0;
    }

    char* nonce_bytes = alloc<char>(4);
    if (nonce_bytes == null) { free(pm.peers); pm.peers = null; return false; }
    mgc_zero(nonce_bytes, 4);
    crypto_rng_bytes(nonce_bytes, 4);
    pm.self_nonce = endian_read_u32_le(nonce_bytes, 0) & 2147483647;
    free(nonce_bytes);
    if (pm.self_nonce == 0) { pm.self_nonce = 1; }

    int fd = net_socket_tcp();
    if (fd < 0) { free(pm.peers); pm.peers = null; return false; }
    if (!net_bind(fd, listen_port) || !net_listen(fd, 16)) {
        net_close(fd);
        free(pm.peers);
        pm.peers = null;
        return false;
    }
    sys_fcntl(fd, MGC_PEER_F_SETFL, MGC_PEER_O_NONBLOCK);
    pm.listen_fd = fd;
    return true;
}

fn mgc_peer_manager_free(MgcPeerManager* pm) -> void {
    if (pm == null) { return; }
    for (int i = 0; i < pm.capacity; i = i + 1) {
        MgcPeer* p = _mgc_peer_at(pm, i);
        if (p != null && p.fd >= 0) { mgc_peer_disconnect(pm, i); }
    }
    if (pm.listen_fd >= 0) {
        net_close(pm.listen_fd);
        pm.listen_fd = -1;
    }
    if (pm.peers != null) { free(pm.peers); }
    pm.peers = null;
    pm.capacity = 0;
    pm.count = 0;
    pm.addrman = null;
    pm.chain = null;
    pm.mempool = null;
}

fn mgc_peer_send(MgcPeerManager* pm, int index, string command, char* payload, int payload_len) -> bool {
    MgcPeer* p = _mgc_peer_at(pm, index);
    if (p == null || p.fd < 0 || pm == null || command == null || payload_len < 0) { return false; }
    if (payload_len > 0 && payload == null) { return false; }
    int frame_len = 0;
    char* frame = mgc_p2p_frame(pm.magic, command, payload, payload_len, &frame_len);
    if (frame == null || frame_len <= 0) {
        if (frame != null) { free(frame); }
        return false;
    }
    int sent = net_send_all(p.fd, frame, frame_len);
    free(frame);
    return sent == frame_len;
}

fn mgc_peer_count(MgcPeerManager* pm) -> int {
    if (pm == null) { return 0; }
    return pm.count;
}

fn _mgc_peer_send_version(MgcPeerManager* pm, int index) -> bool {
    if (pm == null) { return false; }
    int height = mgc_chain_height(pm.chain);
    if (height < 0) { height = 0; }
    ByteWriter w;
    bw_init(&w, 32);
    bool ok = mgc_p2p_write_version(&w, pm.chain_id, height, pm.self_nonce, pm.listen_port);
    if (ok) { ok = mgc_peer_send(pm, index, "version", w.data, w.length); }
    bw_free(&w);
    return ok;
}

fn _mgc_peer_send_getdata(MgcPeerManager* pm, int index, int type, char* hash32) -> bool {
    ByteWriter w;
    bw_init(&w, 64);
    bool ok = mgc_p2p_write_inv(&w, type, hash32);
    if (ok) { ok = mgc_peer_send(pm, index, "getdata", w.data, w.length); }
    bw_free(&w);
    return ok;
}

fn _mgc_peer_send_inv(MgcPeerManager* pm, int index, int type, char* hash32) -> bool {
    ByteWriter w;
    bw_init(&w, 64);
    bool ok = mgc_p2p_write_inv(&w, type, hash32);
    if (ok) { ok = mgc_peer_send(pm, index, "inv", w.data, w.length); }
    bw_free(&w);
    return ok;
}

fn _mgc_peer_send_inv_broadcast(MgcPeerManager* pm, int type, char* hash32, int except_index) -> void {
    if (pm == null || hash32 == null) { return; }
    for (int i = 0; i < pm.capacity; i = i + 1) {
        MgcPeer* p = _mgc_peer_at(pm, i);
        if (p == null || i == except_index || p.fd < 0 || !p.connected) { }
        else { _mgc_peer_send_inv(pm, i, type, hash32); }
    }
}

fn mgc_peer_broadcast_inv(MgcPeerManager* pm, int type, char* hash32) -> void {
    _mgc_peer_send_inv_broadcast(pm, type, hash32, -1);
}

fn _mgc_peer_send_getheaders(MgcPeerManager* pm, int index) -> void {
    if (pm == null || pm.chain == null) { return; }
    char* tip = alloc<char>(32);
    if (tip == null) { return; }
    bool ok = mgc_chain_tip_hash(pm.chain, tip);
    ByteWriter w;
    bw_init(&w, 64);
    if (ok) { ok = mgc_p2p_write_hashes(&w, tip, 1); }
    if (ok) { mgc_peer_send(pm, index, "getheaders", w.data, w.length); }
    bw_free(&w);
    free(tip);
}

fn mgc_peer_connect(MgcPeerManager* pm, int ip0, int ip1, int ip2, int ip3, int port) -> bool {
    if (pm == null || pm.peers == null || port <= 0 || port > 65535) { return false; }
    if (ip0 < 0 || ip0 > 255 || ip1 < 0 || ip1 > 255 ||
        ip2 < 0 || ip2 > 255 || ip3 < 0 || ip3 > 255) { return false; }
    int slot = _mgc_peer_find_free(pm);
    if (slot < 0) { return false; }
    int fd = net_socket_tcp();
    if (fd < 0) { return false; }
    net_set_timeout_ms(fd, 200);
    if (!net_connect(fd, ip0, ip1, ip2, ip3, port)) {
        net_close(fd);
        return false;
    }
    MgcPeer* p = _mgc_peer_at(pm, slot);
    p.fd = fd;
    p.ip0 = ip0; p.ip1 = ip1; p.ip2 = ip2; p.ip3 = ip3; p.port = port;
    p.inbound = false;
    p.connected = true;
    p.verified = false;
    p.nonce = 0;
    p.height = 0;
    p.ban_score = 0;
    p.last_activity = 0;
    p.buf = null;
    p.buf_len = 0;
    p.buf_cap = 0;
    pm.count = pm.count + 1;
    return _mgc_peer_send_version(pm, slot);
}

fn _mgc_peer_handle_version(MgcPeerManager* pm, int index, MgcMsg* m) -> void {
    int cid = 0;
    int height = 0;
    int nonce = 0;
    int port = 0;
    if (!mgc_p2p_read_version(m, &cid, &height, &nonce, &port) || cid != pm.chain_id) {
        _mgc_peer_ban(pm, index, 100);
        return;
    }
    MgcPeer* p = _mgc_peer_at(pm, index);
    if (p == null) { return; }
    p.nonce = nonce;
    p.height = height;
    if (port > 0 && port <= 65535) { p.port = port; }
    mgc_peer_send(pm, index, "verack", null, 0);
    _mgc_peer_send_getheaders(pm, index);
}

fn _mgc_peer_handle_getheaders(MgcPeerManager* pm, int index, MgcMsg* m) -> void {
    if (pm == null || pm.chain == null) { return; }
    MgcChain* c = pm.chain;
    char* locator = alloc<char>(32);
    char* hashes = alloc<char>(MGC_PEER_MAX_HEADERS * 32);
    if (locator == null || hashes == null) {
        if (locator != null) { free(locator); }
        if (hashes != null) { free(hashes); }
        return;
    }
    int count = 0;
    bool ok = mgc_p2p_read_hashes(m, locator, 1, &count);
    int n = 0;
    if (ok && count == 1) {
        int start = mgc_chain_find(c, locator);
        if (start >= 0) {
            int height = c.heights[start] + 1;
            int idx = mgc_chain_at_height(c, height);
            while (idx >= 0 && n < MGC_PEER_MAX_HEADERS) {
                char* src = c.hashes + idx * 32;
                mgc_copy(hashes + n * 32, src, 32);
                n = n + 1;
                height = height + 1;
                idx = mgc_chain_at_height(c, height);
            }
        }
    }
    ByteWriter w;
    bw_init(&w, 64);
    ok = mgc_p2p_write_hashes(&w, hashes, n);
    if (ok) { mgc_peer_send(pm, index, "headers", w.data, w.length); }
    bw_free(&w);
    free(hashes);
    free(locator);
}

fn _mgc_peer_handle_headers(MgcPeerManager* pm, int index, MgcMsg* m) -> void {
    char* hashes = alloc<char>(MGC_PEER_MAX_HEADERS * 32);
    if (hashes == null) { return; }
    int count = 0;
    if (mgc_p2p_read_hashes(m, hashes, MGC_PEER_MAX_HEADERS, &count)) {
        for (int i = 0; i < count; i = i + 1) {
            char* h = hashes + i * 32;
            if (pm.chain == null || mgc_chain_find(pm.chain, h) < 0) {
                _mgc_peer_send_getdata(pm, index, MGC_INV_BLOCK, h);
            }
        }
    }
    free(hashes);
}

fn _mgc_peer_handle_getdata(MgcPeerManager* pm, int index, MgcMsg* m) -> void {
    int type = 0;
    char* hash = alloc<char>(32);
    if (hash == null) { return; }
    if (!mgc_p2p_read_inv(m, &type, hash)) { free(hash); return; }
    if (type == MGC_INV_BLOCK && pm.chain != null) {
        int idx = mgc_chain_find(pm.chain, hash);
        if (idx >= 0) {
            MgcBlock* b = mgc_chain_get(pm.chain, idx);
            if (b != null) {
                int len = 0;
                char* data = mgc_block_serialize(b, &len);
                if (data != null && len > 0) {
                    mgc_peer_send(pm, index, "block", data, len);
                    free(data);
                }
            }
        }
    } else if (type == MGC_INV_TX && pm.mempool != null) {
        MgcMempool* mp = pm.mempool;
        int n = mgc_mempool_count(mp);
        char* ids = mp.txids;
        if (ids != null) {
            for (int i = 0; i < n; i = i + 1) {
                if (mgc_equal(ids + i * 32, hash, 32)) {
                    MgcTx* tx = mgc_mempool_get(pm.mempool, i);
                    if (tx != null) {
                        int len = 0;
                        char* data = mgc_tx_serialize(tx, true, &len);
                        if (data != null && len > 0) {
                            mgc_peer_send(pm, index, "tx", data, len);
                            free(data);
                        }
                    }
                    break;
                }
            }
        }
    }
    free(hash);
}

fn _mgc_peer_handle_inv(MgcPeerManager* pm, int index, MgcMsg* m) -> void {
    int type = 0;
    char* hash = alloc<char>(32);
    if (hash == null) { return; }
    if (!mgc_p2p_read_inv(m, &type, hash)) { free(hash); return; }
    if (type == MGC_INV_BLOCK) {
        if (pm.chain == null || mgc_chain_find(pm.chain, hash) < 0) {
            _mgc_peer_send_getdata(pm, index, MGC_INV_BLOCK, hash);
        }
    } else if (type == MGC_INV_TX) {
        if (!mgc_mempool_has(pm.mempool, hash)) {
            _mgc_peer_send_getdata(pm, index, MGC_INV_TX, hash);
        }
    }
    free(hash);
}

fn _mgc_peer_handle_block(MgcPeerManager* pm, int index, MgcMsg* m) -> void {
    if (pm == null || pm.chain == null) { return; }
    MgcBlock* b = alloc<MgcBlock>(1);
    if (b == null) { return; }
    char* hash = alloc<char>(32);
    if (hash == null) { free(b); return; }
    if (!mgc_block_deserialize(m.payload, m.payload_len, b) || !mgc_block_hash(b, hash)) {
        mgc_block_free(b);
        free(b);
        free(hash);
        _mgc_peer_ban(pm, index, 20);
        return;
    }
    bool reorg = false;
    if (mgc_chain_add_block(pm.chain, b, &reorg)) {
        _mgc_peer_send_inv_broadcast(pm, MGC_INV_BLOCK, hash, index);
    } else {
        _mgc_peer_ban(pm, index, 100);
    }
    free(hash);
}

fn _mgc_peer_handle_tx(MgcPeerManager* pm, int index, MgcMsg* m) -> void {
    if (pm == null || pm.chain == null || pm.mempool == null) { return; }
    MgcTx* tx = alloc<MgcTx>(1);
    if (tx == null) { return; }
    if (!mgc_tx_deserialize(m.payload, m.payload_len, tx)) {
        free(tx);
        _mgc_peer_ban(pm, index, 20);
        return;
    }
    MgcChain* c = pm.chain;
    int height = mgc_chain_height(c);
    if (height < 0) { height = 0; }
    int fee = 0;
    bool ok = mgc_consensus_verify_tx(tx, c.utxo, height, pm.network, pm.chain_id, &fee);
    if (ok) { ok = mgc_mempool_add(pm.mempool, tx); }
    if (ok) {
        char* tid = alloc<char>(32);
        if (tid != null && mgc_tx_txid(tx, tid)) {
            _mgc_peer_send_inv_broadcast(pm, MGC_INV_TX, tid, index);
        }
        if (tid != null) { free(tid); }
    } else {
        _mgc_peer_ban(pm, index, 20);
    }
    mgc_tx_free(tx);
    free(tx);
}

fn _mgc_peer_handle_getaddr(MgcPeerManager* pm, int index) -> void {
    ByteWriter w;
    bw_init(&w, 64);
    int count = mgc_addrman_count(pm.addrman);
    for (int i = 0; i < count; i = i + 1) {
        MgcAddrEntry* e = mgc_addrman_get(pm.addrman, i);
        if (e == null) { break; }
        bw_write_u8(&w, e.ip0);
        bw_write_u8(&w, e.ip1);
        bw_write_u8(&w, e.ip2);
        bw_write_u8(&w, e.ip3);
        bw_write_u32(&w, e.port);
        free(e);
    }
    mgc_peer_send(pm, index, "addr", w.data, w.length);
    bw_free(&w);
}

fn _mgc_peer_handle_addr(MgcPeerManager* pm, MgcMsg* m) -> void {
    if (pm == null || pm.addrman == null || m.payload_len < 8) { return; }
    if ((m.payload_len % 8) != 0) { return; }
    int off = 0;
    while (off + 8 <= m.payload_len) {
        int ip0 = endian_read_u8(m.payload, off);
        int ip1 = endian_read_u8(m.payload, off + 1);
        int ip2 = endian_read_u8(m.payload, off + 2);
        int ip3 = endian_read_u8(m.payload, off + 3);
        int port = endian_read_u32_le(m.payload, off + 4);
        mgc_addrman_add(pm.addrman, ip0, ip1, ip2, ip3, port);
        off = off + 8;
    }
}

fn _mgc_peer_dispatch(MgcPeerManager* pm, int index, MgcMsg* m) -> void {
    if (mgc_p2p_is(m, "version")) { _mgc_peer_handle_version(pm, index, m); return; }
    if (mgc_p2p_is(m, "verack")) {
        MgcPeer* p = _mgc_peer_at(pm, index);
        if (p != null) { p.verified = true; }
        return;
    }
    if (mgc_p2p_is(m, "ping")) {
        mgc_peer_send(pm, index, "pong", m.payload, m.payload_len);
        return;
    }
    if (mgc_p2p_is(m, "pong")) {
        MgcPeer* p = _mgc_peer_at(pm, index);
        if (p != null) { p.last_activity = p.last_activity + 1; }
        return;
    }
    if (mgc_p2p_is(m, "getheaders")) { _mgc_peer_handle_getheaders(pm, index, m); return; }
    if (mgc_p2p_is(m, "headers")) { _mgc_peer_handle_headers(pm, index, m); return; }
    if (mgc_p2p_is(m, "getdata")) { _mgc_peer_handle_getdata(pm, index, m); return; }
    if (mgc_p2p_is(m, "inv")) { _mgc_peer_handle_inv(pm, index, m); return; }
    if (mgc_p2p_is(m, "block")) { _mgc_peer_handle_block(pm, index, m); return; }
    if (mgc_p2p_is(m, "tx")) { _mgc_peer_handle_tx(pm, index, m); return; }
    if (mgc_p2p_is(m, "getaddr")) { _mgc_peer_handle_getaddr(pm, index); return; }
    if (mgc_p2p_is(m, "addr")) { _mgc_peer_handle_addr(pm, m); return; }
}

fn _mgc_peer_accept_ready(MgcPeerManager* pm) -> void {
    int accepted = 0;
    while (accepted < pm.capacity) {
        int fd = net_accept(pm.listen_fd);
        if (fd < 0) { return; }
        int slot = _mgc_peer_find_free(pm);
        if (slot < 0) {
            net_close(fd);
            return;
        }
        net_set_timeout_ms(fd, 200);
        MgcPeer* p = _mgc_peer_at(pm, slot);
        p.fd = fd;
        p.ip0 = 127; p.ip1 = 0; p.ip2 = 0; p.ip3 = 1; p.port = pm.listen_port;
        p.inbound = true;
        p.connected = true;
        p.verified = false;
        p.nonce = 0;
        p.height = 0;
        p.ban_score = 0;
        p.last_activity = 0;
        p.buf = null;
        p.buf_len = 0;
        p.buf_cap = 0;
        pm.count = pm.count + 1;
        _mgc_peer_send_version(pm, slot);
        accepted = accepted + 1;
    }
}

fn _mgc_peer_pump_slot(MgcPeerManager* pm, int index, char* tmp) -> void {
    MgcPeer* p = _mgc_peer_at(pm, index);
    if (p == null || p.fd < 0) { return; }
    int n = net_recv_into(p.fd, tmp, MGC_PEER_RECV_CHUNK);
    if (n == 0) { mgc_peer_disconnect(pm, index); return; }
    if (n < 0) { return; }

    int need = p.buf_len + n;
    if (need > MGC_PEER_BUF_MAX) {
        _mgc_peer_ban(pm, index, 100);
        return;
    }
    if (p.buf == null || p.buf_cap < need) {
        int cap = 8192;
        while (cap < need && cap < MGC_PEER_BUF_MAX) { cap = cap * 2; }
        if (cap < need) { cap = need; }
        char* fresh = alloc<char>(cap);
        if (fresh == null) {
            _mgc_peer_ban(pm, index, 100);
            return;
        }
        if (p.buf_len > 0) { mgc_copy(fresh, p.buf, p.buf_len); }
        if (p.buf != null) { free(p.buf); }
        p.buf = fresh;
        p.buf_cap = cap;
    }
    mgc_copy(p.buf + p.buf_len, tmp, n);
    p.buf_len = need;

    while (p.buf_len >= MGC_P2P_HEADER_SIZE) {
        int payload_len = endian_read_u32_le(p.buf, 16);
        if (payload_len < 0 || payload_len > MGC_P2P_MAX_PAYLOAD) {
            _mgc_peer_ban(pm, index, 100);
            return;
        }
        int frame_len = MGC_P2P_HEADER_SIZE + payload_len;
        if (p.buf_len < frame_len) { return; }

        MgcMsg msg;
        mgc_msg_init(&msg);
        bool parsed = mgc_p2p_parse(p.buf, frame_len, pm.magic, &msg);
        bool handshake = mgc_p2p_is(&msg, "version") || mgc_p2p_is(&msg, "verack");
        if (parsed && (handshake || p.verified)) { _mgc_peer_dispatch(pm, index, &msg); }
        if (!parsed) { _mgc_peer_ban(pm, index, 100); }
        mgc_msg_free(&msg);
        if (p.fd < 0) { return; }

        int left = p.buf_len - frame_len;
        if (left > 0) { mgc_copy(p.buf, p.buf + frame_len, left); }
        p.buf_len = left;
    }
}

fn mgc_peer_pump(MgcPeerManager* pm, int timeout_ms) -> int {
    if (pm == null || pm.peers == null || pm.listen_fd < 0) { return 0; }
    int nfds = pm.capacity + 1;
    char* fds = alloc<char>(nfds * 8);
    char* tmp = alloc<char>(MGC_PEER_RECV_CHUNK);
    if (fds == null || tmp == null) {
        if (fds != null) { free(fds); }
        if (tmp != null) { free(tmp); }
        return 0;
    }
    for (int i = 0; i < nfds * 8; i = i + 1) { *(fds + i) = 0; }
    endian_write_u32_le(fds, 0, pm.listen_fd);
    endian_write_u16_le(fds, 4, MGC_PEER_POLLIN_FLAG);
    endian_write_u16_le(fds, 6, 0);
    for (int i = 0; i < pm.capacity; i = i + 1) {
        MgcPeer* p = _mgc_peer_at(pm, i);
        int off = (i + 1) * 8;
        int fd = -1;
        if (p != null && p.fd >= 0) { fd = p.fd; }
        endian_write_u32_le(fds, off, fd);
        endian_write_u16_le(fds, off + 4, MGC_PEER_POLLIN_FLAG);
        endian_write_u16_le(fds, off + 6, 0);
    }

    int ready = sys_poll(fds, nfds, timeout_ms);
    int handled = 0;
    if (ready > 0) {
        int listen_revents = endian_read_u16_le(fds, 6);
        if ((listen_revents & (MGC_PEER_POLLIN_FLAG | MGC_PEER_POLLERR_FLAG | MGC_PEER_POLLHUP_FLAG)) != 0) {
            _mgc_peer_accept_ready(pm);
            handled = handled + 1;
        }
        for (int i = 0; i < pm.capacity; i = i + 1) {
            MgcPeer* p = _mgc_peer_at(pm, i);
            if (p == null || p.fd < 0) { }
            else {
                int revents = endian_read_u16_le(fds, (i + 1) * 8 + 6);
                if (revents != 0) {
                    _mgc_peer_pump_slot(pm, i, tmp);
                    handled = handled + 1;
                }
            }
        }
    }
    free(fds);
    free(tmp);
    return handled;
}
