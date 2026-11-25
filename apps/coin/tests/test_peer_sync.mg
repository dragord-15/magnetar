// Two-node regtest sync: B learns three mined blocks from A over TCP.

use "../lib/mining.mg";
use "../lib/peer.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    MgcUtxoSet setA;
    MgcUtxoSet setB;
    MgcChain chainA;
    MgcChain chainB;
    MgcMempool mpA;
    MgcMempool mpB;
    MgcAddrMan addrsA;
    MgcAddrMan addrsB;
    MgcPeerManager pmA;
    MgcPeerManager pmB;

    check_bool("utxo A init", mgc_utxo_init(&setA, 4096), true, &failures);
    check_bool("utxo B init", mgc_utxo_init(&setB, 4096), true, &failures);
    check_bool("chain A init", mgc_chain_init(&chainA, MGC_NETWORK_REGTEST, 4096, &setA), true, &failures);
    check_bool("chain B init", mgc_chain_init(&chainB, MGC_NETWORK_REGTEST, 4096, &setB), true, &failures);
    check_bool("mempool A init", mgc_mempool_init(&mpA, 64), true, &failures);
    check_bool("mempool B init", mgc_mempool_init(&mpB, 64), true, &failures);
    check_bool("addrman A init", mgc_addrman_init(&addrsA, 64), true, &failures);
    check_bool("addrman B init", mgc_addrman_init(&addrsB, 64), true, &failures);
    check_bool("genesis A", mgc_chain_add_genesis(&chainA), true, &failures);
    check_bool("genesis B", mgc_chain_add_genesis(&chainB), true, &failures);

    char* h160 = alloc<char>(20);
    char* payout = alloc<char>(25);
    char* tipA = alloc<char>(32);
    char* tipB = alloc<char>(32);
    if (h160 == null || payout == null || tipA == null || tipB == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    int attempts = 0;
    bool reorg = false;
    for (int i = 0; i < 3; i = i + 1) {
        MgcBlock* b = alloc<MgcBlock>(1);
        if (b == null) { print_str("FAIL alloc\n"); return 1; }
        mgc_zero(h160, 20);
        *(h160 + 0) = cast<char>(i + 1);
        mgc_script_p2pkh(h160, payout);
        check_bool("build block A", mgc_mining_build_block(&chainA, &mpA, payout, 25, b), true, &failures);
        check_bool("mine block A", mgc_mining_mine(b, 100000, &attempts), true, &failures);
        check_bool("add block A", mgc_chain_add_block(&chainA, b, &reorg), true, &failures);
    }
    check_int("A height", mgc_chain_height(&chainA), 3, &failures);
    check_bool("A tip hash", mgc_chain_tip_hash(&chainA, tipA), true, &failures);

    check_bool("manager A init", mgc_peer_manager_init(&pmA, MGC_NETWORK_REGTEST, 29341, 4096,
                                                       &addrsA, &chainA, &mpA), true, &failures);
    check_bool("manager B init", mgc_peer_manager_init(&pmB, MGC_NETWORK_REGTEST, 29342, 4096,
                                                       &addrsB, &chainB, &mpB), true, &failures);
    check_bool("B connect to A", mgc_peer_connect(&pmB, 127, 0, 0, 1, 29341), true, &failures);

    for (int i = 0; i < 200; i = i + 1) {
        mgc_peer_pump(&pmA, 5);
        mgc_peer_pump(&pmB, 5);
        if (mgc_chain_height(&chainB) == 3) {
            mgc_chain_tip_hash(&chainB, tipB);
            if (mgc_equal(tipA, tipB, 32)) { break; }
        }
    }

    check_int("B height synced", mgc_chain_height(&chainB), 3, &failures);
    check_bool("B tip hash", mgc_chain_tip_hash(&chainB, tipB), true, &failures);
    check_bool("tips equal", mgc_equal(tipA, tipB, 32), true, &failures);
    check_bool("A peer count", mgc_peer_count(&pmA) >= 1, true, &failures);
    check_bool("B peer count", mgc_peer_count(&pmB) >= 1, true, &failures);

    int badfd = net_socket_tcp();
    check_bool("malformed peer socket", badfd >= 0, true, &failures);
    if (badfd >= 0) {
        net_set_timeout_ms(badfd, 100);
        check_bool("malformed peer connect", net_connect_localhost(badfd, 29341), true, &failures);
        int before = mgc_peer_count(&pmA);
        for (int i = 0; i < 50 && mgc_peer_count(&pmA) <= before; i = i + 1) {
            mgc_peer_pump(&pmA, 5);
        }
        check_int("malformed peer accepted", mgc_peer_count(&pmA), before + 1, &failures);
        char* payload = alloc<char>(1);
        int bad_len = 0;
        char* bad_frame = null;
        if (payload != null) {
            *payload = cast<char>(1);
            bad_frame = mgc_p2p_frame(pmA.magic, "ping", payload, 1, &bad_len);
        }
        if (bad_frame != null && bad_len > 20) {
            *(bad_frame + 20) = cast<char>((cast<int>(*(bad_frame + 20)) ^ 1) & 255);
            net_send_all(badfd, bad_frame, bad_len);
            for (int i = 0; i < 50 && mgc_peer_count(&pmA) > before; i = i + 1) {
                mgc_peer_pump(&pmA, 5);
            }
        }
        check_int("malformed peer disconnected", mgc_peer_count(&pmA), before, &failures);
        check_int("good peer survived malformed message", mgc_peer_count(&pmB), 1, &failures);
        if (bad_frame != null) { free(bad_frame); }
        if (payload != null) { free(payload); }
        net_close(badfd);
    }

    mgc_peer_manager_free(&pmB);
    mgc_peer_manager_free(&pmA);
    mgc_mempool_free(&mpB);
    mgc_mempool_free(&mpA);
    mgc_addrman_free(&addrsB);
    mgc_addrman_free(&addrsA);
    mgc_chain_free(&chainB);
    mgc_chain_free(&chainA);
    mgc_utxo_free(&setB);
    mgc_utxo_free(&setA);
    free(tipB);
    free(tipA);
    free(payout);
    free(h160);
    return test_report("test_peer_sync", failures);
}
