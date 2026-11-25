// Magnetar Coin — private keys, WIF and P2PKH addresses.

use "base58.mg";
use "bigint.mg";
use "hash.mg";
use "params.mg";
use "secp256k1.mg";
use "util.mg";
use "../../lib/crypto.mg";

fn mgc_key_validate(char* priv32) -> bool {
    if (priv32 == null) { return false; }
    int* d = alloc<int>(16);
    int* n = alloc<int>(16);
    if (d == null || n == null) {
        if (d != null) { free(d); }
        if (n != null) { free(n); }
        return false;
    }
    secp_n(n);
    mgc_big_from_bytes_be(d, priv32, 32);
    bool ok = !mgc_big_is_zero(d) && mgc_big_cmp(d, n) < 0;
    free(d); free(n);
    return ok;
}

// Cryptographically random private key in [1, n-1].
fn mgc_key_generate(char* priv32) -> bool {
    if (priv32 == null) { return false; }
    char* tmp = alloc<char>(32);
    if (tmp == null) { return false; }
    for (int attempt = 0; attempt < 100; attempt = attempt + 1) {
        int got = crypto_rng_bytes(tmp, 32);
        if (got != 32) { continue; }
        if (mgc_key_validate(tmp)) {
            mgc_copy(priv32, tmp, 32);
            mgc_zero(tmp, 32);
            free(tmp);
            return true;
        }
    }
    mgc_zero(tmp, 32);
    free(tmp);
    return false;
}

fn mgc_privkey_to_pubkey(char* priv32, char* out33) -> bool {
    if (priv32 == null || out33 == null) { return false; }
    int* d = alloc<int>(16);
    if (d == null) { return false; }
    mgc_big_from_bytes_be(d, priv32, 32);
    bool ok = secp_pubkey_from_priv(d, out33);
    free(d);
    return ok;
}

fn mgc_pubkey_hash160(char* pub, int pub_len, char* out20) -> bool {
    if (pub == null || out20 == null || pub_len <= 0) { return false; }
    mgc_hash160(pub, pub_len, out20);
    return true;
}

fn mgc_p2pkh_from_hash160(char* h160, int network) -> string {
    if (h160 == null) { return ""; }
    char* payload = alloc<char>(21);
    if (payload == null) { return ""; }
    payload[0] = cast<char>(mgc_address_prefix(network) & 255);
    mgc_copy(payload + 1, h160, 20);
    string addr = base58check_encode(payload, 21);
    free(payload);
    return addr;
}

fn mgc_address_from_pubkey(char* pub, int pub_len, int network) -> string {
    if (pub == null || pub_len <= 0) { return ""; }
    char* h160 = alloc<char>(20);
    if (h160 == null) { return ""; }
    mgc_hash160(pub, pub_len, h160);
    string addr = mgc_p2pkh_from_hash160(h160, network);
    free(h160);
    return addr;
}

fn mgc_address_decode(string addr, int network, char* out20) -> bool {
    if (addr == null || out20 == null) { return false; }
    int plen = 0;
    char* payload = base58check_decode(addr, &plen);
    if (payload == null || plen != 21) {
        if (payload != null) { free(payload); }
        return false;
    }
    bool ok = (cast<int>(*(payload + 0)) & 255) == mgc_address_prefix(network);
    if (ok) { mgc_copy(out20, payload + 1, 20); }
    free(payload);
    return ok;
}

// Compressed WIF: Base58Check(wif_prefix || priv32 || 0x01).
fn mgc_wif_encode(char* priv32, int network, bool compressed) -> string {
    if (priv32 == null) { return ""; }
    int plen = 33;
    if (compressed) { plen = 34; }
    char* payload = alloc<char>(plen);
    if (payload == null) { return ""; }
    payload[0] = cast<char>(mgc_wif_prefix(network) & 255);
    mgc_copy(payload + 1, priv32, 32);
    if (compressed) { payload[33] = cast<char>(1); }
    string wif = base58check_encode(payload, plen);
    mgc_zero(payload, plen);
    free(payload);
    return wif;
}

fn mgc_wif_decode(string wif, int network, bool* compressed, char* out32) -> bool {
    if (wif == null || out32 == null) { return false; }
    int plen = 0;
    char* payload = base58check_decode(wif, &plen);
    if (payload == null) { return false; }
    bool ok = false;
    bool is_compressed = false;
    if ((plen == 33 || plen == 34) && (cast<int>(*(payload + 0)) & 255) == mgc_wif_prefix(network)) {
        if (plen == 34) {
            is_compressed = (cast<int>(*(payload + 33)) & 255) == 1;
            ok = is_compressed;
        } else {
            ok = true;
        }
    }
    if (ok) {
        mgc_copy(out32, payload + 1, 32);
        if (compressed != null) { *compressed = is_compressed; }
    }
    mgc_zero(payload, plen);
    free(payload);
    return ok;
}

fn mgc_address_from_privkey(char* priv32, int network) -> string {
    if (priv32 == null) { return ""; }
    char* pub = alloc<char>(33);
    if (pub == null) { return ""; }
    if (!mgc_privkey_to_pubkey(priv32, pub)) { free(pub); return ""; }
    string addr = mgc_address_from_pubkey(pub, 33, network);
    free(pub);
    return addr;
}
