// MGC node: datadir, chain, UTXO, mempool, wallet, addresses and peers wiring.

use "storage.mg";
use "chain.mg";
use "utxo.mg";
use "mempool.mg";
use "wallet.mg";
use "addrman.mg";
use "peer.mg";
use "mining.mg";
use "keys.mg";
use "script.mg";
use "params.mg";
use "../../lib/crypto.mg";
use "../../lib/string.mg";

struct MgcNode {
    int network; int p2p_port; int rpc_port;
    MgcChain chain; MgcUtxoSet utxo; MgcMempool mempool; MgcWallet wallet;
    MgcAddrMan addrman; MgcPeerManager peers;
    int lock_fd; char* datadir; char* cookie; bool stop;
    MgcChain* cref; MgcUtxoSet* uref; MgcMempool* mref;
    MgcWallet* wref; MgcAddrMan* aref; MgcPeerManager* pref;
    int loaded_count;
}

fn _mgc_node_chain_cap() -> int { return 8192; }
fn _mgc_node_utxo_cap() -> int { return 32768; }
fn _mgc_node_mempool_cap() -> int { return 4096; }
fn _mgc_node_wallet_cap() -> int { return 64; }
fn _mgc_node_addr_cap() -> int { return 256; }
fn _mgc_node_peer_cap() -> int { return 32; }
fn _mgc_node_cookie_cap() -> int { return 64; }
fn _mgc_node_datadir_cap() -> int { return 512; }
fn _mgc_node_mine_attempts() -> int { return 2000000; }

fn _mgc_node_sync_chain(MgcNode* n) -> void {
    if (n == null || n.cref == null) { return; }
    MgcChain tmp;
    mgc_copy(cast<char*>(&tmp), cast<char*>(n.cref), sizeof(MgcChain));
    n.chain = tmp;
}

fn _mgc_node_sync_utxo(MgcNode* n) -> void {
    if (n == null || n.uref == null) { return; }
    MgcUtxoSet tmp;
    mgc_copy(cast<char*>(&tmp), cast<char*>(n.uref), sizeof(MgcUtxoSet));
    n.utxo = tmp;
}

fn _mgc_node_sync_mempool(MgcNode* n) -> void {
    if (n == null || n.mref == null) { return; }
    MgcMempool tmp;
    mgc_copy(cast<char*>(&tmp), cast<char*>(n.mref), sizeof(MgcMempool));
    n.mempool = tmp;
}

fn _mgc_node_sync_wallet(MgcNode* n) -> void {
    if (n == null || n.wref == null) { return; }
    MgcWallet tmp;
    mgc_copy(cast<char*>(&tmp), cast<char*>(n.wref), sizeof(MgcWallet));
    n.wallet = tmp;
}

fn _mgc_node_sync_addrman(MgcNode* n) -> void {
    if (n == null || n.aref == null) { return; }
    MgcAddrMan tmp;
    mgc_copy(cast<char*>(&tmp), cast<char*>(n.aref), sizeof(MgcAddrMan));
    n.addrman = tmp;
}

fn _mgc_node_sync_peers(MgcNode* n) -> void {
    if (n == null || n.pref == null) { return; }
    MgcPeerManager tmp;
    mgc_copy(cast<char*>(&tmp), cast<char*>(n.pref), sizeof(MgcPeerManager));
    n.peers = tmp;
}

fn _mgc_node_copy_text(char* dst, int cap, string src) -> bool {
    if (dst == null || cap <= 0 || src == null) { return false; }
    char* p = cast<char*>(src);
    int i = 0;
    while (i < cap - 1 && *(p + i) != 0) {
        *(dst + i) = *(p + i);
        i = i + 1;
    }
    *(dst + i) = 0;
    return i > 0;
}

fn _mgc_node_parse_addr(string text, int* ip0, int* ip1, int* ip2, int* ip3, int* port) -> bool {
    if (text == null || ip0 == null || ip1 == null || ip2 == null || ip3 == null || port == null) { return false; }
    char* p = cast<char*>(text);
    int n = len(text);
    int parts[5];
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
        parts[count] = value;
        count = count + 1;
        if (i < n) {
            char sep = *(p + i);
            if (sep != 46 && sep != 58) { return false; }
        }
    }
    if (count != 5) { return false; }
    if (parts[0] > 255 || parts[1] > 255 || parts[2] > 255 || parts[3] > 255) { return false; }
    if (parts[4] < 1 || parts[4] > 65535) { return false; }
    *ip0 = parts[0];
    *ip1 = parts[1];
    *ip2 = parts[2];
    *ip3 = parts[3];
    *port = parts[4];
    return true;
}

fn mgc_node_init(MgcNode* n, int network, string datadir, int p2p_port, int rpc_port) -> bool {
    if (n == null || datadir == null || p2p_port < 1 || p2p_port > 65535 ||
        rpc_port < 1 || rpc_port > 65535) { return false; }
    mgc_zero(cast<char*>(n), sizeof(MgcNode));
    n.network = network;
    n.p2p_port = p2p_port;
    n.rpc_port = rpc_port;
    n.lock_fd = -1;

    n.datadir = alloc<char>(_mgc_node_datadir_cap());
    n.cookie = alloc<char>(_mgc_node_cookie_cap());
    n.cref = alloc<MgcChain>(1);
    n.uref = alloc<MgcUtxoSet>(1);
    n.mref = alloc<MgcMempool>(1);
    n.wref = alloc<MgcWallet>(1);
    n.aref = alloc<MgcAddrMan>(1);
    n.pref = alloc<MgcPeerManager>(1);
    if (n.datadir == null || n.cookie == null || n.cref == null || n.uref == null ||
        n.mref == null || n.wref == null || n.aref == null || n.pref == null) {
        mgc_node_shutdown(n);
        return false;
    }
    if (!_mgc_node_copy_text(n.datadir, _mgc_node_datadir_cap(), datadir)) {
        mgc_node_shutdown(n);
        return false;
    }

    if (!mgc_storage_init_datadir(cast<string>(n.datadir))) {
        mgc_node_shutdown(n);
        return false;
    }
    n.lock_fd = mgc_storage_lock(cast<string>(n.datadir));
    if (n.lock_fd < 0) {
        mgc_node_shutdown(n);
        return false;
    }
    string cookie = mgc_storage_write_cookie(cast<string>(n.datadir));
    if (!_mgc_node_copy_text(n.cookie, _mgc_node_cookie_cap(), cookie)) {
        mgc_node_shutdown(n);
        return false;
    }

    if (!mgc_utxo_init(n.uref, _mgc_node_utxo_cap())) {
        mgc_node_shutdown(n);
        return false;
    }
    if (!mgc_chain_init(n.cref, network, _mgc_node_chain_cap(), n.uref)) {
        mgc_node_shutdown(n);
        return false;
    }
    if (!mgc_chain_add_genesis(n.cref)) {
        mgc_node_shutdown(n);
        return false;
    }
    if (!mgc_mempool_init(n.mref, _mgc_node_mempool_cap())) {
        mgc_node_shutdown(n);
        return false;
    }
    if (!mgc_wallet_init(n.wref, network, _mgc_node_wallet_cap())) {
        mgc_node_shutdown(n);
        return false;
    }
    if (!mgc_addrman_init(n.aref, _mgc_node_addr_cap())) {
        mgc_node_shutdown(n);
        return false;
    }
    MgcPeerManager* pref_at_init = n.pref;
    mgc_zero(cast<char*>(pref_at_init), sizeof(MgcPeerManager));
    pref_at_init.listen_fd = -1;

    _mgc_node_sync_chain(n);
    _mgc_node_sync_utxo(n);
    _mgc_node_sync_mempool(n);
    _mgc_node_sync_wallet(n);
    _mgc_node_sync_addrman(n);
    _mgc_node_sync_peers(n);
    return true;
}

fn mgc_node_load(MgcNode* n) -> bool {
    if (n == null || n.cref == null || n.uref == null || n.wref == null || n.aref == null) { return false; }
    string dd = cast<string>(n.datadir);
    int loaded = mgc_storage_load_blocks(dd, n.cref);
    if (loaded < 0) { loaded = 0; }
    n.loaded_count = loaded;
    // The block log is the source of truth: load_blocks already rebuilt the UTXO
    // set from genesis. Loading a possibly stale utxo.dat afterwards would roll
    // the chainstate back while the chain tip stays ahead (crash recovery bug).

    string wallet_path = mgc_storage_path(dd, "wallet/wallet.dat");
    MgcWallet* wallet_at_load = n.wref;
    mgc_wallet_load_unlocked(wallet_at_load, wallet_path, "");
    wallet_at_load.network = n.network;
    string addr_path = mgc_storage_path(dd, "peers.txt");
    mgc_addrman_load(n.aref, addr_path);

    _mgc_node_sync_chain(n);
    _mgc_node_sync_utxo(n);
    _mgc_node_sync_wallet(n);
    _mgc_node_sync_addrman(n);
    return true;
}

fn mgc_node_save(MgcNode* n) -> bool {
    if (n == null || n.cref == null || n.uref == null || n.wref == null || n.aref == null) { return false; }
    string dd = cast<string>(n.datadir);
    MgcChain* c = n.cref;
    int total = c.count;
    int from = n.loaded_count;
    if (from < 0) { from = 0; }
    bool ok = true;
    for (int i = from; i < total && ok; i = i + 1) {
        MgcBlock* b = mgc_chain_get(c, i);
        if (b != null) { ok = mgc_storage_append_block(dd, b); }
    }
    if (ok) { ok = mgc_storage_save_utxo(dd, n.uref); }
    string addr_path = mgc_storage_path(dd, "peers.txt");
    if (ok) { ok = mgc_addrman_save(n.aref, addr_path); }
    MgcWallet* w = n.wref;
    if (ok && w.key_count > 0 && !w.locked) {
        if (w.ciphertext == null || w.mac == null) { mgc_wallet_encrypt(w, ""); }
        string wallet_path = mgc_storage_path(dd, "wallet/wallet.dat");
        ok = mgc_wallet_save(w, wallet_path);
    }
    _mgc_node_sync_wallet(n);
    return ok;
}

fn mgc_node_start_peers(MgcNode* n) -> bool {
    if (n == null || n.pref == null || n.cref == null || n.mref == null || n.aref == null) { return false; }
    bool ok = mgc_peer_manager_init(n.pref, n.network, n.p2p_port, _mgc_node_peer_cap(),
                                   n.aref, n.cref, n.mref);
    if (!ok) { return false; }
    int count = mgc_addrman_count(n.aref);
    for (int i = 0; i < count; i = i + 1) {
        MgcAddrEntry* e = mgc_addrman_get(n.aref, i);
        if (e == null) { continue; }
        mgc_peer_connect(n.pref, e.ip0, e.ip1, e.ip2, e.ip3, e.port);
        free(e);
    }
    _mgc_node_sync_peers(n);
    return true;
}

fn mgc_node_addnode(MgcNode* n, string ip_port) -> bool {
    if (n == null || n.aref == null || ip_port == null) { return false; }
    int ip0 = 0;
    int ip1 = 0;
    int ip2 = 0;
    int ip3 = 0;
    int port = 0;
    if (!_mgc_node_parse_addr(ip_port, &ip0, &ip1, &ip2, &ip3, &port)) { return false; }
    bool ok = mgc_addrman_add(n.aref, ip0, ip1, ip2, ip3, port);
    _mgc_node_sync_addrman(n);
    MgcPeerManager* pref_for_add = n.pref;
    if (ok && pref_for_add != null && pref_for_add.listen_fd >= 0) {
        ok = mgc_peer_connect(pref_for_add, ip0, ip1, ip2, ip3, port);
        _mgc_node_sync_peers(n);
    }
    return ok;
}

fn _mgc_node_persist_wallet(MgcNode* n) -> bool {
    if (n == null || n.wref == null) { return false; }
    MgcWallet* w = n.wref;
    if (w.locked || w.key_count <= 0) { return false; }
    if (w.ciphertext == null || w.mac == null) {
        if (!mgc_wallet_encrypt(w, "")) { return false; }
    }
    string path = mgc_storage_path(cast<string>(n.datadir), "wallet/wallet.dat");
    bool ok = mgc_wallet_save(w, path);
    free(cast<char*>(path));
    return ok;
}

fn mgc_node_generate(MgcNode* n, int count) -> int {
    if (n == null || n.cref == null || n.wref == null || n.mref == null || n.uref == null ||
        count <= 0) { return 0; }
    if (count > 1000) { count = 1000; }
    MgcWallet* w = n.wref;
    MgcChain* chain_for_gen = n.cref;
    MgcPeerManager* pref_for_gen = n.pref;

    string addr = "";
    if (w.key_count > 0) {
        addr = mgc_wallet_address_at(w, 0);
    } else {
        addr = mgc_wallet_new_address(w);
        if (addr == "" || !_mgc_node_persist_wallet(n)) {
            if (addr != "") { free(cast<char*>(addr)); }
            return 0;
        }
    }
    if (addr == "") { return 0; }

    char* h160 = alloc<char>(20);
    char* script = alloc<char>(25);
    if (h160 == null || script == null) {
        if (h160 != null) { free(h160); }
        if (script != null) { free(script); }
        free(cast<char*>(addr));
        return 0;
    }
    bool decoded = mgc_address_decode(addr, n.network, h160);
    free(cast<char*>(addr));
    if (decoded) { mgc_script_p2pkh(h160, script); }
    free(h160);
    if (!decoded) {
        free(script);
        return 0;
    }

    int added = 0;
    for (int i = 0; i < count; i = i + 1) {
        MgcBlock* b = alloc<MgcBlock>(1);
        if (b == null) { break; }
        if (!mgc_mining_build_block(n.cref, n.mref, script, 25, b)) {
            free(b);
            break;
        }
        int attempts = 0;
        if (!mgc_mining_mine(b, _mgc_node_mine_attempts(), &attempts)) {
            mgc_block_free(b);
            free(b);
            break;
        }
        bool reorg = false;
        if (!mgc_chain_add_block(chain_for_gen, b, &reorg)) { break; }
        added = added + 1;
        int idx = chain_for_gen.count - 1;
        MgcBlock* stored = mgc_chain_get(chain_for_gen, idx);
        if (stored != null) {
            mgc_storage_append_block(cast<string>(n.datadir), stored);
        }
        char* block_hash = alloc<char>(32);
        if (block_hash != null) {
            if (mgc_block_hash(b, block_hash) && pref_for_gen != null) {
                mgc_peer_broadcast_inv(pref_for_gen, MGC_INV_BLOCK, block_hash);
            }
            free(block_hash);
        }
    }
    free(script);
    _mgc_node_sync_chain(n);
    _mgc_node_sync_utxo(n);
    _mgc_node_sync_wallet(n);
    return added;
}

fn mgc_node_shutdown(MgcNode* n) -> void {
    if (n == null) { return; }
    if (n.pref != null) { mgc_peer_manager_free(n.pref); }
    if (n.wref != null) { mgc_wallet_free(n.wref); }
    if (n.cref != null) { mgc_chain_free(n.cref); }
    if (n.uref != null) { mgc_utxo_free(n.uref); }
    if (n.mref != null) { mgc_mempool_free(n.mref); }
    if (n.aref != null) { mgc_addrman_free(n.aref); }
    if (n.lock_fd >= 0) { sys_close(n.lock_fd); }
    if (n.datadir != null) { free(n.datadir); }
    if (n.cookie != null) { mgc_zero(n.cookie, _mgc_node_cookie_cap()); free(n.cookie); }
    if (n.pref != null) { free(n.pref); }
    if (n.cref != null) { free(n.cref); }
    if (n.uref != null) { free(n.uref); }
    if (n.mref != null) { free(n.mref); }
    if (n.wref != null) { free(n.wref); }
    if (n.aref != null) { free(n.aref); }
    mgc_zero(cast<char*>(n), sizeof(MgcNode));
    n.lock_fd = -1;
    n.stop = true;
}
