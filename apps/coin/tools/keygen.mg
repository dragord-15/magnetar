use "../lib/keys.mg";
use "../lib/params.mg";
use "../lib/util.mg";
use "../../lib/crypto.mg";

extern fn print_str(string s) -> void;

fn main() -> int {
    int network = MGC_NETWORK_REGTEST;
    char* priv = alloc<char>(32);
    char* pub = alloc<char>(33);
    if (priv == null || pub == null) {
        print_str("error: out of memory\n");
        return 1;
    }
    if (!mgc_key_generate(priv)) {
        print_str("error: could not generate key\n");
        free(priv);
        free(pub);
        return 1;
    }
    if (!mgc_privkey_to_pubkey(priv, pub)) {
        print_str("error: could not derive public key\n");
        mgc_zero(priv, 32);
        free(priv);
        free(pub);
        return 1;
    }

    string priv_hex = crypto_hex_encode(priv, 32);
    string pub_hex = crypto_hex_encode(pub, 33);
    string wif = mgc_wif_encode(priv, network, true);
    string addr = mgc_address_from_pubkey(pub, 33, network);

    print_str("network: regtest\n");
    print_str("private: "); print_str(priv_hex); print_str("\n");
    print_str("public:  "); print_str(pub_hex); print_str("\n");
    print_str("wif:     "); print_str(wif); print_str("\n");
    print_str("address: "); print_str(addr); print_str("\n");
    print_str("Keep the private key and WIF secret.\n");

    mgc_zero(priv, 32);
    free(priv);
    free(pub);
    return 0;
}
