// Encrypted wallet unit tests: persistence roundtrip, balance, signing and tamper rejection.

use "../lib/wallet.mg";
use "../lib/consensus.mg";
use "../../lib/crypto.mg";
use "test_common.mg";

fn _mgc_wallet_test_contains(char* hay, int hlen, char* needle, int nlen) -> bool {
    if (hay == null || needle == null || nlen <= 0 || hlen < nlen) { return false; }
    for (int i = 0; i <= hlen - nlen; i = i + 1) {
        bool same = true;
        for (int j = 0; j < nlen && same; j = j + 1) {
            if (*(hay + i + j) != *(needle + j)) { same = false; }
        }
        if (same) { return true; }
    }
    return false;
}

fn main() -> int {
    int failures = 0;
    string path = "/tmp/mgc_wallet_test.dat";
    sys_unlink(path);

    MgcWallet w;
    check_bool("wallet init", mgc_wallet_init(&w, MGC_NETWORK_REGTEST, 8), true, &failures);
    string addr0 = mgc_wallet_new_address(&w);
    string addr1 = mgc_wallet_new_address(&w);
    check_int("wallet key count", mgc_wallet_key_count(&w), 2, &failures);
    check_bool("two distinct addresses", addr0 != addr1, true, &failures);
    check_string("address at 0", mgc_wallet_address_at(&w, 0), addr0, &failures);
    check_bool("encrypt", mgc_wallet_encrypt(&w, "secret"), true, &failures);
    check_bool("save", mgc_wallet_save(&w, path), true, &failures);

    char* file_data = null;
    int file_len = 0;
    check_bool("read wallet file", mgc_storage_read(path, &file_data, &file_len), true, &failures);
    if (file_data != null) {
        for (int k = 0; k < 2; k = k + 1) {
            char* priv = w.privkeys + k * 32;
            string hex = crypto_hex_encode(priv, 32);
            check_bool("no plaintext key hex", str_index_of(cast<string>(file_data), hex) < 0, true, &failures);
            check_bool("no plaintext key bytes", _mgc_wallet_test_contains(file_data, file_len, priv, 32), false, &failures);
            free(cast<char*>(hex));
        }
        free(file_data);
    } else {
        check_bool("wallet file present", false, true, &failures);
    }

    MgcWallet wrong_wallet;
    check_bool("wrong password load", mgc_wallet_load(&wrong_wallet, path, "wrong"), false, &failures);
    mgc_wallet_free(&wrong_wallet);

    MgcWallet loaded;
    check_bool("load wallet", mgc_wallet_load(&loaded, path, "secret"), true, &failures);
    check_bool("locked after load", loaded.locked, true, &failures);
    check_int("loaded key count", mgc_wallet_key_count(&loaded), 2, &failures);
    check_bool("unlock wrong password", mgc_wallet_unlock(&loaded, "wrong"), false, &failures);
    check_bool("still locked", loaded.locked, true, &failures);
    check_bool("unlock", mgc_wallet_unlock(&loaded, "secret"), true, &failures);
    check_string("restored address", mgc_wallet_address_at(&loaded, 0), addr0, &failures);

    MgcWallet unlocked_load;
    check_bool("load unlocked wallet", mgc_wallet_load_unlocked(&unlocked_load, path, "secret"), true, &failures);
    check_bool("unlocked after load", unlocked_load.locked, false, &failures);
    check_int("unlocked key count", mgc_wallet_key_count(&unlocked_load), 2, &failures);
    check_string("unlocked address", mgc_wallet_address_at(&unlocked_load, 0), addr0, &failures);
    mgc_wallet_free(&unlocked_load);

    char* h160 = alloc<char>(20);
    char* script = alloc<char>(25);
    char* txid = alloc<char>(32);
    if (h160 == null || script == null || txid == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    check_bool("decode address", mgc_address_decode(addr0, MGC_NETWORK_REGTEST, h160), true, &failures);
    mgc_script_p2pkh(h160, script);
    for (int i = 0; i < 32; i = i + 1) { *(txid + i) = cast<char>(i + 1); }

    MgcUtxoSet utxo;
    check_bool("utxo init", mgc_utxo_init(&utxo, 16), true, &failures);
    check_bool("add wallet utxo", mgc_utxo_add(&utxo, txid, 0, 100000, script, 25, 1, false), true, &failures);
    check_int("wallet balance", mgc_wallet_balance(&loaded, &utxo), 100000, &failures);

    MgcTx tx;
    check_bool("create tx", mgc_wallet_create_tx(&loaded, &utxo, addr1, MGC_NETWORK_REGTEST,
                                                 40000, 1000, 20, &tx), true, &failures);
    check_int("tx inputs", tx.in_count, 1, &failures);
    check_int("tx outputs", tx.out_count, 2, &failures);
    if (tx.out_count == 2) {
        check_int("tx recipient value", tx.output_values[0], 40000, &failures);
        check_int("tx change value", tx.output_values[1], 59000, &failures);
    }
    check_bool("sign tx", mgc_wallet_sign_tx(&loaded, &utxo, MGC_NETWORK_REGTEST,
                                             mgc_chain_id(MGC_NETWORK_REGTEST), &tx), true, &failures);

    char* txid32 = alloc<char>(32);
    char* txid_copy = alloc<char>(32);
    if (txid32 == null || txid_copy == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    check_bool("original txid", mgc_tx_txid(&tx, txid32), true, &failures);
    int tx_raw_len = 0;
    char* tx_raw = mgc_tx_serialize(&tx, true, &tx_raw_len);
    MgcTx restored;
    if (tx_raw == null || !mgc_tx_deserialize(tx_raw, tx_raw_len, &restored)) {
        check_bool("tx roundtrip", false, true, &failures);
    } else {
        check_bool("txid roundtrip", mgc_tx_txid(&restored, txid_copy), true, &failures);
        check_bool("txid match", mgc_equal(txid32, txid_copy, 32), true, &failures);
        mgc_tx_free(&restored);
    }
    if (tx_raw != null) { free(tx_raw); }

    int fee = -1;
    check_bool("consensus verify", mgc_consensus_verify_tx(&tx, &utxo, 20, MGC_NETWORK_REGTEST,
                                                          mgc_chain_id(MGC_NETWORK_REGTEST), &fee), true, &failures);
    check_int("consensus fee", fee, 1000, &failures);

    tx.output_values[0] = 200000;
    check_bool("tamper rejected", mgc_consensus_verify_tx(&tx, &utxo, 20, MGC_NETWORK_REGTEST,
                                                          mgc_chain_id(MGC_NETWORK_REGTEST), &fee), false, &failures);
    tx.output_values[0] = 40000;

    mgc_tx_free(&tx);
    free(txid_copy);
    free(txid32);
    mgc_utxo_free(&utxo);
    free(txid);
    free(script);
    free(h160);
    mgc_wallet_free(&loaded);
    mgc_wallet_free(&w);
    return test_report("test_wallet", failures);
}
