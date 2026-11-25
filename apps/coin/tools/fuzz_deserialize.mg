// Magnetar Coin — randomized deserialization robustness check for tx, block and P2P frames.

use "../lib/block.mg";
use "../lib/p2p.mg";
use "../lib/params.mg";
use "../../lib/crypto.mg";

extern fn print_str(string s) -> void;

fn main() -> int {
    int samples = 1000000;
    int magic = mgc_p2p_magic(MGC_NETWORK_REGTEST);
    char* buf = alloc<char>(512);
    MgcTx tx;
    MgcBlock block;
    MgcMsg msg;
    mgc_tx_init(&tx);
    mgc_block_init(&block);
    mgc_msg_init(&msg);
    if (buf == null || block.prev_block == null || block.merkle_root == null) {
        print_str("error: out of memory\n");
        if (buf != null) { free(buf); }
        return 1;
    }

    for (int i = 0; i < samples; i = i + 1) {
        int length = i % 513;
        if (length > 0) {
            int got = crypto_rng_bytes(buf, length);
            if (got != length) {
                print_str("error: random source failed\n");
                mgc_tx_free(&tx);
                mgc_block_free(&block);
                if (block.prev_block != null) { free(block.prev_block); }
                if (block.merkle_root != null) { free(block.merkle_root); }
                free(buf);
                return 1;
            }
        }
        mgc_tx_deserialize(buf, length, &tx);
        mgc_tx_free(&tx);
        if (mgc_block_deserialize(buf, length, &block)) {
            mgc_block_free(&block);
        }
        if (mgc_p2p_parse(buf, length, magic, &msg)) {
            mgc_msg_free(&msg);
        }
    }

    mgc_tx_free(&tx);
    mgc_block_free(&block);
    if (block.prev_block != null) { free(block.prev_block); }
    if (block.merkle_root != null) { free(block.merkle_root); }
    free(buf);

    print_str("samples: ");
    print(samples);
    print_str("\n");
    print_str("PASS\n");
    return 0;
}
