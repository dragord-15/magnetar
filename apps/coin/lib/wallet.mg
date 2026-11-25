// MGC encrypted wallet. File: raw "MGCW" v1 | network u32 | iterations u32 | salt[16] | iv[16] | ct_len u32 | AES-256-CBC ciphertext | HMAC-SHA256 mac[32]; plaintext is [u32 count][32-byte keys]* and is never written.

use "params.mg";
use "util.mg";
use "endian.mg";
use "hash.mg";
use "keys.mg";
use "secp256k1.mg";
use "script.mg";
use "sighash.mg";
use "tx.mg";
use "utxo.mg";
use "storage.mg";
use "../../lib/crypto.mg";
use "../../lib/string.mg";

struct MgcWallet {
    int network; int capacity; int key_count;
    char* privkeys; char* pubkeys; bool locked;
    char* salt; char* iv; char* ciphertext; int ciphertext_len; char* mac; int iterations;
}

fn _mgc_wallet_iterations() -> int { return 200000; }
// Empty-password wallets are only obfuscated, not protected: a fast KDF keeps
// regtest/dev startup usable. A non-empty password always uses the full count.
fn _mgc_wallet_iterations_for(string password) -> int {
    if (password == null || password == "") { return 1000; }
    return _mgc_wallet_iterations();
}
fn _mgc_wallet_default_capacity() -> int { return 16; }
fn _mgc_wallet_max_keys() -> int { return 10000; }
fn _mgc_wallet_version() -> int { return 1; }

fn _mgc_wallet_clear(MgcWallet* w) -> void {
    if (w == null) { return; }
    int cap = w.capacity;
    int ctlen = w.ciphertext_len;
    if (w.privkeys != null) { mgc_zero(w.privkeys, cap * 32); free(w.privkeys); }
    if (w.pubkeys != null) { free(w.pubkeys); }
    if (w.salt != null) { free(w.salt); }
    if (w.iv != null) { free(w.iv); }
    if (w.ciphertext != null) { mgc_zero(w.ciphertext, ctlen); free(w.ciphertext); }
    if (w.mac != null) { free(w.mac); }
    w.network = 0;
    w.capacity = 0;
    w.key_count = 0;
    w.privkeys = null;
    w.pubkeys = null;
    w.locked = false;
    w.salt = null;
    w.iv = null;
    w.ciphertext = null;
    w.ciphertext_len = 0;
    w.mac = null;
    w.iterations = 0;
}

fn mgc_wallet_init(MgcWallet* w, int network, int capacity) -> bool {
    if (w == null || capacity <= 0 || capacity > _mgc_wallet_max_keys()) { return false; }
    w.network = network;
    w.capacity = capacity;
    w.key_count = 0;
    w.privkeys = null;
    w.pubkeys = null;
    w.locked = false;
    w.salt = null;
    w.iv = null;
    w.ciphertext = null;
    w.ciphertext_len = 0;
    w.mac = null;
    w.iterations = _mgc_wallet_iterations();
    w.privkeys = alloc<char>(capacity * 32);
    w.pubkeys = alloc<char>(capacity * 33);
    if (w.privkeys == null || w.pubkeys == null) {
        _mgc_wallet_clear(w);
        return false;
    }
    mgc_zero(w.privkeys, capacity * 32);
    mgc_zero(w.pubkeys, capacity * 33);
    return true;
}

fn mgc_wallet_free(MgcWallet* w) -> void {
    _mgc_wallet_clear(w);
}

fn _mgc_wallet_ensure_salt(MgcWallet* w) -> bool {
    if (w.salt != null) { return true; }
    char* salt_bytes = alloc<char>(8);
    if (salt_bytes == null) { return false; }
    if (crypto_rng_bytes(salt_bytes, 8) != 8) { free(salt_bytes); return false; }
    string hex = crypto_hex_encode(salt_bytes, 8);
    w.salt = alloc<char>(17);
    if (w.salt != null) {
        for (int i = 0; i < 16; i = i + 1) { *(w.salt + i) = *(cast<char*>(hex) + i); }
        *(w.salt + 16) = cast<char>(0);
    }
    free(cast<char*>(hex));
    free(salt_bytes);
    return w.salt != null;
}

fn _mgc_wallet_ensure_iv(MgcWallet* w) -> bool {
    if (w.iv != null) { return true; }
    w.iv = alloc<char>(16);
    if (w.iv == null) { return false; }
    if (crypto_rng_bytes(w.iv, 16) != 16) {
        free(w.iv);
        w.iv = null;
        return false;
    }
    return true;
}

fn _mgc_wallet_derive_raw(string password, string salt_text, int iterations, char* enc_key, char* mac_key_hex) -> bool {
    int got = crypto_pbkdf2_sha256_raw(password, salt_text, iterations, enc_key, 32);
    if (got != 32) { return false; }
    char* seed = alloc<char>(39);
    char* digest = alloc<char>(32);
    if (seed == null || digest == null) {
        if (seed != null) { free(seed); }
        if (digest != null) { free(digest); }
        return false;
    }
    for (int i = 0; i < 7; i = i + 1) { *(seed + i) = *(cast<char*>("MGC-MAC") + i); }
    mgc_copy(seed + 7, enc_key, 32);
    crypto_sha256_raw(seed, 39, digest);
    string hex = crypto_hex_encode(digest, 32);
    if (hex == null || len(hex) != 64) {
        free(seed); free(digest);
        return false;
    }
    for (int i = 0; i < 64; i = i + 1) { *(mac_key_hex + i) = *(cast<char*>(hex) + i); }
    *(mac_key_hex + 64) = cast<char>(0);
    free(cast<char*>(hex));
    free(seed);
    free(digest);
    return true;
}

fn _mgc_wallet_derive(MgcWallet* w, string password, char* enc_key, char* mac_key_hex) -> bool {
    if (w == null || w.salt == null) { return false; }
    return _mgc_wallet_derive_raw(password, cast<string>(w.salt), w.iterations, enc_key, mac_key_hex);
}

fn _mgc_wallet_mac(string mac_key_hex, char* iv, char* ct, int ct_len, char* out32) -> void {
    char* msg = alloc<char>(16 + ct_len);
    if (msg == null) { mgc_zero(out32, 32); return; }
    mgc_copy(msg, iv, 16);
    mgc_copy(msg + 16, ct, ct_len);
    crypto_hmac_sha256_raw(mac_key_hex, msg, 16 + ct_len, out32);
    free(msg);
}

fn mgc_wallet_encrypt(MgcWallet* w, string password) -> bool {
    if (w == null || password == null || w.locked || w.privkeys == null || w.pubkeys == null) { return false; }
    if (w.key_count <= 0 || w.key_count > w.capacity) { return false; }
    w.iterations = _mgc_wallet_iterations_for(password);
    if (!_mgc_wallet_ensure_salt(w)) { return false; }
    if (!_mgc_wallet_ensure_iv(w)) { return false; }

    int plain_len = 4 + 32 * w.key_count;
    char* plain = alloc<char>(plain_len + 32);
    char* enc_key = alloc<char>(32);
    char* mac_key_hex = alloc<char>(65);
    if (plain == null || enc_key == null || mac_key_hex == null) {
        if (plain != null) { free(plain); }
        if (enc_key != null) { free(enc_key); }
        if (mac_key_hex != null) { free(mac_key_hex); }
        return false;
    }
    mgc_zero(plain, plain_len + 32);
    endian_write_u32_le(plain, 0, w.key_count);
    for (int i = 0; i < w.key_count; i = i + 1) {
        mgc_copy(plain + 4 + i * 32, w.privkeys + i * 32, 32);
    }
    bool ok = _mgc_wallet_derive(w, password, enc_key, mac_key_hex);
    char* ct = null;
    int ct_len = 0;
    if (ok) {
        ct = alloc<char>(plain_len + 32);
        if (ct == null) { ok = false; }
    }
    if (ok) {
        ct_len = crypto_aes_cbc_encrypt_raw(plain, plain_len, enc_key, 32, w.iv, ct);
        if (ct_len <= 0 || ct_len > plain_len + 32) { ok = false; }
    }
    char* mac = null;
    if (ok) {
        mac = alloc<char>(32);
        if (mac == null) { ok = false; }
    }
    if (ok) { _mgc_wallet_mac(mac_key_hex, w.iv, ct, ct_len, mac); }
    if (ok) {
        if (w.ciphertext != null) { mgc_zero(w.ciphertext, w.ciphertext_len); free(w.ciphertext); }
        if (w.mac != null) { free(w.mac); }
        w.ciphertext = ct;
        w.ciphertext_len = ct_len;
        w.mac = mac;
        ct = null;
        mac = null;
    }
    if (ct != null) { free(ct); }
    if (mac != null) { free(mac); }
    mgc_zero(plain, plain_len + 32);
    mgc_zero(enc_key, 32);
    mgc_zero(mac_key_hex, 65);
    free(plain);
    free(enc_key);
    free(mac_key_hex);
    return ok;
}

fn _mgc_wallet_wipe_keys(MgcWallet* w) -> void {
    if (w.privkeys != null) { mgc_zero(w.privkeys, w.capacity * 32); }
    if (w.pubkeys != null) { mgc_zero(w.pubkeys, w.capacity * 33); }
    w.locked = true;
}

fn mgc_wallet_unlock(MgcWallet* w, string password) -> bool {
    if (w == null || password == null) { return false; }
    if (w.privkeys == null || w.pubkeys == null || w.capacity <= 0) { return false; }
    if (w.salt == null || w.iv == null || w.ciphertext == null || w.mac == null) { return false; }
    if (w.ciphertext_len <= 0 || w.ciphertext_len > w.capacity * 32 + 64) { return false; }

    char* enc_key = alloc<char>(32);
    char* mac_key_hex = alloc<char>(65);
    if (enc_key == null || mac_key_hex == null) {
        if (enc_key != null) { free(enc_key); }
        if (mac_key_hex != null) { free(mac_key_hex); }
        return false;
    }
    bool ok = _mgc_wallet_derive(w, password, enc_key, mac_key_hex);
    char* expected = alloc<char>(32);
    if (expected == null) { ok = false; }
    if (ok) { _mgc_wallet_mac(mac_key_hex, w.iv, w.ciphertext, w.ciphertext_len, expected); }
    if (ok) {
        int diff = 0;
        for (int i = 0; i < 32; i = i + 1) {
            int a = cast<int>(*(w.mac + i)) & 255;
            int b = cast<int>(*(expected + i)) & 255;
            diff = diff | (a ^ b);
        }
        if (diff != 0) { ok = false; }
    }
    char* plain = alloc<char>(w.ciphertext_len + 32);
    int plain_len = 0;
    int count = 0;
    if (plain == null) { ok = false; }
    if (ok) {
        plain_len = crypto_aes_cbc_decrypt_raw(w.ciphertext, w.ciphertext_len, enc_key, 32, w.iv, plain);
        count = endian_read_u32_le(plain, 0);
        if (plain_len < 4 || (plain_len - 4) != 32 * count || count <= 0 || count > w.capacity) { ok = false; }
    }
    char* pub = alloc<char>(33);
    if (pub == null) { ok = false; }
    if (ok) {
        for (int i = 0; i < count && ok; i = i + 1) {
            char* priv = plain + 4 + i * 32;
            if (!mgc_key_validate(priv)) { ok = false; }
            if (ok && !mgc_privkey_to_pubkey(priv, pub)) { ok = false; }
            if (ok) {
                mgc_copy(w.privkeys + i * 32, priv, 32);
                mgc_copy(w.pubkeys + i * 33, pub, 33);
            }
        }
    }
    if (ok) {
        mgc_zero(w.privkeys + count * 32, (w.capacity - count) * 32);
        mgc_zero(w.pubkeys + count * 33, (w.capacity - count) * 33);
        w.key_count = count;
        w.locked = false;
    }
    if (!ok) { _mgc_wallet_wipe_keys(w); }
    if (plain != null) { mgc_zero(plain, w.ciphertext_len + 32); free(plain); }
    if (expected != null) { free(expected); }
    if (pub != null) { mgc_zero(pub, 33); free(pub); }
    mgc_zero(enc_key, 32);
    mgc_zero(mac_key_hex, 65);
    free(enc_key);
    free(mac_key_hex);
    return ok;
}

fn mgc_wallet_new_address(MgcWallet* w) -> string {
    if (w == null || w.locked || w.privkeys == null || w.pubkeys == null) { return ""; }
    if (w.key_count < 0 || w.key_count >= w.capacity) { return ""; }
    char* priv = alloc<char>(32);
    char* pub = alloc<char>(33);
    if (priv == null || pub == null) {
        if (priv != null) { free(priv); }
        if (pub != null) { free(pub); }
        return "";
    }
    string addr = "";
    if (mgc_key_generate(priv) && mgc_privkey_to_pubkey(priv, pub)) {
        mgc_copy(w.privkeys + w.key_count * 32, priv, 32);
        mgc_copy(w.pubkeys + w.key_count * 33, pub, 33);
        w.key_count = w.key_count + 1;
        if (w.ciphertext != null) { mgc_zero(w.ciphertext, w.ciphertext_len); free(w.ciphertext); }
        if (w.mac != null) { free(w.mac); }
        w.ciphertext = null;
        w.ciphertext_len = 0;
        w.mac = null;
        addr = mgc_address_from_pubkey(pub, 33, w.network);
    }
    mgc_zero(priv, 32);
    free(priv);
    free(pub);
    return addr;
}

fn mgc_wallet_address_at(MgcWallet* w, int i) -> string {
    if (w == null || w.pubkeys == null || i < 0 || i >= w.key_count || i >= w.capacity) { return ""; }
    return mgc_address_from_pubkey(w.pubkeys + i * 33, 33, w.network);
}

fn mgc_wallet_key_count(MgcWallet* w) -> int {
    if (w == null) { return 0; }
    return w.key_count;
}

fn _mgc_wallet_find_index(MgcWallet* w, char* hash160) -> int {
    if (w == null || w.pubkeys == null || hash160 == null) { return -1; }
    char* h = alloc<char>(20);
    if (h == null) { return -1; }
    int found = -1;
    for (int i = 0; i < w.key_count && found < 0; i = i + 1) {
        mgc_hash160(w.pubkeys + i * 33, 33, h);
        if (mgc_equal(h, hash160, 20)) { found = i; }
    }
    free(h);
    return found;
}

fn mgc_wallet_find_privkey(MgcWallet* w, char* hash160, char* out32) -> bool {
    if (w == null || w.locked || w.privkeys == null || hash160 == null || out32 == null) { return false; }
    int i = _mgc_wallet_find_index(w, hash160);
    if (i < 0) { return false; }
    mgc_copy(out32, w.privkeys + i * 32, 32);
    return true;
}

fn mgc_wallet_save(MgcWallet* w, string path) -> bool {
    if (w == null || path == null) { return false; }
    if (w.ciphertext == null || w.mac == null || w.ciphertext_len <= 0 || w.salt == null || w.iv == null) {
        return false;
    }
    int total = 52 + w.ciphertext_len + 32;
    char* buf = alloc<char>(total);
    if (buf == null) { return false; }
    mgc_zero(buf, total);
    for (int i = 0; i < 4; i = i + 1) { *(buf + i) = *(cast<char*>("MGCW") + i); }
    endian_write_u32_le(buf, 4, _mgc_wallet_version());
    endian_write_u32_le(buf, 8, w.network);
    endian_write_u32_le(buf, 12, w.iterations);
    mgc_copy(buf + 16, w.salt, 16);
    mgc_copy(buf + 32, w.iv, 16);
    endian_write_u32_le(buf, 48, w.ciphertext_len);
    mgc_copy(buf + 52, w.ciphertext, w.ciphertext_len);
    mgc_copy(buf + 52 + w.ciphertext_len, w.mac, 32);
    bool ok = mgc_storage_atomic_write(path, buf, total);
    mgc_zero(buf, total);
    free(buf);
    return ok;
}

fn _mgc_wallet_load_impl(MgcWallet* w, string path, string password, bool unlock) -> bool {
    if (w == null || path == null || password == null) { return false; }
    char* data = null;
    int data_len = 0;
    if (!mgc_storage_read(path, &data, &data_len)) {
        mgc_wallet_init(w, MGC_NETWORK_REGTEST, _mgc_wallet_default_capacity());
        return true;
    }
    bool ok = false;
    int network = 0;
    int iterations = 0;
    int ct_len = 0;
    int count = 0;
    char* salt = null;
    char* iv = null;
    char* enc_key = null;
    char* mac_key_hex = null;
    char* expected = null;
    char* plain = null;

    if (data_len >= 84 && mgc_equal(data, cast<char*>("MGCW"), 4)) {
        network = endian_read_u32_le(data, 8);
        iterations = endian_read_u32_le(data, 12);
        ct_len = endian_read_u32_le(data, 48);
        if (endian_read_u32_le(data, 4) == _mgc_wallet_version() &&
            iterations > 0 && iterations <= 10000000 && ct_len > 0 && (ct_len % 16) == 0 &&
            data_len == 52 + ct_len + 32) {
            salt = alloc<char>(17);
            iv = alloc<char>(16);
            enc_key = alloc<char>(32);
            mac_key_hex = alloc<char>(65);
            expected = alloc<char>(32);
            if (salt != null && iv != null && enc_key != null && mac_key_hex != null && expected != null) {
                mgc_copy(salt, data + 16, 16);
                *(salt + 16) = cast<char>(0);
                mgc_copy(iv, data + 32, 16);
                ok = true;
            }
        }
    }
    if (ok) {
        bool derived = _mgc_wallet_derive_raw(password, cast<string>(salt), iterations, enc_key, mac_key_hex);
        if (!derived) { ok = false; }
    }
    if (ok) {
        char* msg = alloc<char>(16 + ct_len);
        if (msg == null) { ok = false; }
        if (ok) {
            mgc_copy(msg, data + 32, 16);
            mgc_copy(msg + 16, data + 52, ct_len);
            crypto_hmac_sha256_raw(mac_key_hex, msg, 16 + ct_len, expected);
            int diff = 0;
            for (int i = 0; i < 32; i = i + 1) {
                int a = cast<int>(*(data + 52 + ct_len + i)) & 255;
                int b = cast<int>(*(expected + i)) & 255;
                diff = diff | (a ^ b);
            }
            if (diff != 0) { ok = false; }
            free(msg);
        }
    }
    if (ok) {
        plain = alloc<char>(ct_len + 32);
        if (plain == null) { ok = false; }
    }
    if (ok) {
        int plain_len = crypto_aes_cbc_decrypt_raw(data + 52, ct_len, enc_key, 32, iv, plain);
        count = endian_read_u32_le(plain, 0);
        if (plain_len < 4 || (plain_len - 4) != 32 * count || count <= 0 || count > _mgc_wallet_max_keys()) { ok = false; }
    }
    if (ok) {
        int cap = count;
        if (cap < _mgc_wallet_default_capacity()) { cap = _mgc_wallet_default_capacity(); }
        if (mgc_wallet_init(w, network, cap)) {
            w.iterations = iterations;
            w.key_count = count;
            w.salt = alloc<char>(17);
            w.iv = alloc<char>(16);
            if (w.salt != null) {
                mgc_copy(w.salt, salt, 16);
                *(w.salt + 16) = cast<char>(0);
            }
            if (w.iv != null) { mgc_copy(w.iv, iv, 16); }
            w.ciphertext = alloc<char>(ct_len);
            if (w.ciphertext != null) { mgc_copy(w.ciphertext, data + 52, ct_len); }
            w.ciphertext_len = ct_len;
            w.mac = alloc<char>(32);
            if (w.mac != null) { mgc_copy(w.mac, data + 52 + ct_len, 32); }
            if (w.salt == null || w.iv == null || w.ciphertext == null || w.mac == null) {
                _mgc_wallet_clear(w);
                ok = false;
            }
            w.locked = true;
        } else {
            ok = false;
        }
    }
    if (ok && unlock) {
        char* pub = alloc<char>(33);
        if (pub == null) {
            ok = false;
        } else {
            for (int i = 0; i < count && ok; i = i + 1) {
                char* priv = plain + 4 + i * 32;
                if (!mgc_key_validate(priv)) { ok = false; }
                if (ok && !mgc_privkey_to_pubkey(priv, pub)) { ok = false; }
                if (ok) {
                    mgc_copy(w.privkeys + i * 32, priv, 32);
                    mgc_copy(w.pubkeys + i * 33, pub, 33);
                }
            }
            mgc_zero(pub, 33);
            free(pub);
            if (ok) {
                w.key_count = count;
                w.locked = false;
            }
        }
        if (!ok) { _mgc_wallet_wipe_keys(w); }
    }
    if (plain != null) { mgc_zero(plain, ct_len + 32); free(plain); }
    if (expected != null) { free(expected); }
    if (mac_key_hex != null) { mgc_zero(mac_key_hex, 65); free(mac_key_hex); }
    if (enc_key != null) { mgc_zero(enc_key, 32); free(enc_key); }
    if (salt != null) { free(salt); }
    if (iv != null) { free(iv); }
    free(data);
    if (!ok) { mgc_wallet_init(w, MGC_NETWORK_REGTEST, _mgc_wallet_default_capacity()); }
    return ok;
}

fn mgc_wallet_load(MgcWallet* w, string path, string password) -> bool {
    return _mgc_wallet_load_impl(w, path, password, false);
}

fn mgc_wallet_load_unlocked(MgcWallet* w, string path, string password) -> bool {
    return _mgc_wallet_load_impl(w, path, password, true);
}

fn mgc_wallet_balance(MgcWallet* w, MgcUtxoSet* utxo) -> int {
    if (w == null || utxo == null || w.pubkeys == null || w.key_count <= 0) { return 0; }
    if (utxo.states == null || utxo.capacity <= 0) { return 0; }
    char* h160 = alloc<char>(20);
    if (h160 == null) { return 0; }
    int limit = mgc_max_money();
    int total = 0;
    for (int i = 0; i < utxo.capacity; i = i + 1) {
        if (utxo.states[i] == 1) {
            if (mgc_script_p2pkh_hash160(utxo.scripts[i], utxo.script_lens[i], h160)) {
                int j = _mgc_wallet_find_index(w, h160);
                if (j >= 0) {
                    int v = utxo.values[i];
                    if (v < 0 || v > limit - total) { total = -1; }
                    else { total = total + v; }
                }
            }
        }
        if (total < 0) { break; }
    }
    free(h160);
    return total;
}

fn mgc_wallet_create_tx(MgcWallet* w, MgcUtxoSet* utxo, string to_address, int network,
                        int amount, int fee, int tip_height, MgcTx* out) -> bool {
    if (out != null) { mgc_tx_init(out); }
    if (w == null || utxo == null || out == null || to_address == null) { return false; }
    if (w.pubkeys == null || w.key_count <= 0 || w.locked) { return false; }
    if (amount <= 0 || fee < 0 || utxo.states == null || utxo.capacity <= 0) { return false; }
    int limit = mgc_max_money();
    if (amount > limit || fee > limit - amount) { return false; }
    int need = amount + fee;

    int* slots = alloc<int>(utxo.capacity);
    int* vals = alloc<int>(utxo.capacity);
    char* h160 = alloc<char>(20);
    char* ph = alloc<char>(20);
    char* script = alloc<char>(25);
    if (slots == null || vals == null || h160 == null || ph == null || script == null) {
        if (slots != null) { free(slots); }
        if (vals != null) { free(vals); }
        if (h160 != null) { free(h160); }
        if (ph != null) { free(ph); }
        if (script != null) { free(script); }
        return false;
    }
    int maturity = mgc_coinbase_maturity(network);
    int candidates = 0;
    for (int i = 0; i < utxo.capacity; i = i + 1) {
        if (utxo.states[i] == 1) {
            bool eligible = true;
            if (utxo.coinbase_flags[i] && utxo.heights[i] + maturity > tip_height) { eligible = false; }
            if (eligible && !mgc_script_p2pkh_hash160(utxo.scripts[i], utxo.script_lens[i], h160)) { eligible = false; }
            if (eligible) {
                int found = -1;
                for (int j = 0; j < w.key_count && found < 0; j = j + 1) {
                    mgc_hash160(w.pubkeys + j * 33, 33, ph);
                    if (mgc_equal(ph, h160, 20)) { found = j; }
                }
                if (found < 0) { eligible = false; }
            }
            if (eligible) {
                slots[candidates] = i;
                vals[candidates] = utxo.values[i];
                candidates = candidates + 1;
            }
        }
    }

    for (int i = 1; i < candidates; i = i + 1) {
        int vk = vals[i];
        int sk = slots[i];
        int j = i - 1;
        while (j >= 0 && vals[j] < vk) {
            vals[j + 1] = vals[j];
            slots[j + 1] = slots[j];
            j = j - 1;
        }
        vals[j + 1] = vk;
        slots[j + 1] = sk;
    }

    int total = 0;
    int selected = 0;
    bool ok = true;
    while (total < need && selected < candidates && ok) {
        int slot = slots[selected];
        int v = vals[selected];
        if (v <= 0 || v > limit - total) { ok = false; }
        if (ok && !mgc_tx_add_input(out, utxo.keys + slot * 36,
                                    endian_read_u32_le(utxo.keys, slot * 36 + 32),
                                    null, 0, 4294967295)) { ok = false; }
        if (ok) { total = total + v; }
        selected = selected + 1;
    }
    if (total < need) { ok = false; }

    if (ok && !mgc_address_decode(to_address, network, h160)) { ok = false; }
    if (ok) {
        mgc_script_p2pkh(h160, script);
        if (!mgc_tx_add_output(out, amount, script, 25)) { ok = false; }
    }
    int change = total - need;
    if (ok && change > 0) {
        mgc_hash160(w.pubkeys, 33, h160);
        mgc_script_p2pkh(h160, script);
        if (!mgc_tx_add_output(out, change, script, 25)) { ok = false; }
    }

    free(slots);
    free(vals);
    free(h160);
    free(ph);
    free(script);
    if (!ok) { mgc_tx_free(out); }
    return ok;
}

fn mgc_wallet_sign_tx(MgcWallet* w, MgcUtxoSet* utxo, int network, int chain_id, MgcTx* tx) -> bool {
    if (w == null || utxo == null || tx == null || w.locked) { return false; }
    if (w.privkeys == null || w.pubkeys == null || tx.in_count <= 0) { return false; }
    int count = tx.in_count;
    int* values = alloc<int>(count);
    char** scripts = alloc<char*>(count);
    int* lens = alloc<int>(count);
    char* h160 = alloc<char>(20);
    char* ph = alloc<char>(20);
    char* priv = alloc<char>(32);
    char* pub = alloc<char>(33);
    char* digest = alloc<char>(32);
    char* der = alloc<char>(80);
    char* sig_script = alloc<char>(160);
    if (values == null || scripts == null || lens == null || h160 == null || ph == null ||
        priv == null || pub == null || digest == null || der == null || sig_script == null) {
        if (values != null) { free(values); }
        if (scripts != null) { free(scripts); }
        if (lens != null) { free(lens); }
        if (h160 != null) { free(h160); }
        if (ph != null) { free(ph); }
        if (priv != null) { free(priv); }
        if (pub != null) { free(pub); }
        if (digest != null) { free(digest); }
        if (der != null) { free(der); }
        if (sig_script != null) { free(sig_script); }
        return false;
    }
    for (int i = 0; i < count; i = i + 1) {
        values[i] = 0;
        scripts[i] = null;
        lens[i] = 0;
    }
    bool ok = true;
    for (int i = 0; i < count && ok; i = i + 1) {
        MgcUtxo prev;
        if (!mgc_utxo_get(utxo, tx.prev_txids + i * 32, tx.prev_indices[i], &prev)) { ok = false; }
        if (ok) {
            scripts[i] = prev.script;
            lens[i] = prev.script_len;
            values[i] = prev.value;
            prev.script = null;
            mgc_utxo_result_free(&prev);
        }
    }
    if (ok) {
        for (int i = 0; i < count && ok; i = i + 1) {
            if (!mgc_script_p2pkh_hash160(scripts[i], lens[i], h160)) { ok = false; }
            int key_index = -1;
            if (ok) {
                for (int j = 0; j < w.key_count && key_index < 0; j = j + 1) {
                    mgc_hash160(w.pubkeys + j * 33, 33, ph);
                    if (mgc_equal(ph, h160, 20)) { key_index = j; }
                }
                if (key_index < 0) { ok = false; }
            }
            int der_len = 0;
            if (ok) {
                mgc_copy(priv, w.privkeys + key_index * 32, 32);
                ok = mgc_sighash(tx, i, values, scripts, lens, chain_id, digest);
                if (ok) { ok = secp_ecdsa_sign(digest, priv, der, &der_len); }
                mgc_zero(priv, 32);
            }
            int script_len = 0;
            if (ok) {
                mgc_copy(pub, w.pubkeys + key_index * 33, 33);
                ok = mgc_script_sig(der, der_len, pub, 33, sig_script, &script_len);
            }
            if (ok) { ok = mgc_tx_set_input_script(tx, i, sig_script, script_len); }
        }
    }
    for (int i = 0; i < count; i = i + 1) {
        if (scripts[i] != null) { free(scripts[i]); }
    }
    mgc_zero(priv, 32);
    mgc_zero(der, 80);
    free(values);
    free(scripts);
    free(lens);
    free(h160);
    free(ph);
    free(priv);
    free(pub);
    free(digest);
    free(der);
    free(sig_script);
    return ok;
}
