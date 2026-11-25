// Magnetar Coin — print deterministic genesis hashes, bits and timestamps for all networks.

use "../lib/chain.mg";
use "../../lib/crypto.mg";

extern fn print_str(string s) -> void;

fn _mgc_genesis_one(int network, string name) -> bool {
    MgcUtxoSet set;
    MgcChain chain;
    if (!mgc_utxo_init(&set, 1024)) { return false; }
    if (!mgc_chain_init(&chain, network, 16, &set)) {
        mgc_utxo_free(&set);
        return false;
    }
    if (!mgc_chain_add_genesis(&chain)) {
        mgc_chain_free(&chain);
        mgc_utxo_free(&set);
        return false;
    }
    MgcBlock* genesis = mgc_chain_best_block(&chain);
    string hash_hex = crypto_hex_encode(chain.hashes, 32);
    print_str("network: ");
    print_str(name);
    print_str("\n");
    print_str("genesis hash: ");
    print_str(hash_hex);
    print_str("\n");
    print_str("genesis bits: ");
    print(genesis.bits);
    print_str("\n");
    print_str("genesis timestamp: ");
    print(genesis.timestamp);
    print_str("\n");
    free(cast<char*>(hash_hex));

    mgc_chain_free(&chain);
    mgc_utxo_free(&set);
    return true;
}

fn main() -> int {
    if (!_mgc_genesis_one(MGC_NETWORK_REGTEST, "regtest")) { return 1; }
    if (!_mgc_genesis_one(MGC_NETWORK_TEST, "test")) { return 1; }
    if (!_mgc_genesis_one(MGC_NETWORK_MAIN, "main")) { return 1; }
    return 0;
}
