// Magnetar Coin — secp256k1 point arithmetic and ECDSA.
// Pure Magnetar. Uses 16-limb (base 2^16) big integers from bigint.mg.
// Points use Jacobian coordinates kept in three separate 16-limb arrays.
// Avoid words reserved by Magnetar (base/borrow/rbuf/...).

use "bigint.mg";
use "hash.mg";
use "../../lib/crypto.mg";

fn secp_p(int* out) -> void { mgc_big_from_hex(out, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F"); }
fn secp_n(int* out) -> void { mgc_big_from_hex(out, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"); }
fn secp_n_half(int* out) -> void { mgc_big_from_hex(out, "7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0"); }
fn secp_gx(int* out) -> void { mgc_big_from_hex(out, "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"); }
fn secp_gy(int* out) -> void { mgc_big_from_hex(out, "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8"); }
fn secp_sqrt_exp(int* out) -> void { mgc_big_from_hex(out, "3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFFFFF0C"); }

fn _secp_one(int* a) -> void { mgc_big_set_u32(a, 1); }
fn _secp_small(int* a, int v) -> void { mgc_big_set_u32(a, v); }

fn _secp_point_infinity(int* x, int* y, int* z) -> void {
    mgc_big_zero(x); _secp_one(y); mgc_big_zero(z);
}

fn _secp_point_is_infinity(int* z) -> bool {
    return mgc_big_is_zero(z);
}

fn _secp_copy_point(int* dx, int* dy, int* dz, int* sx, int* sy, int* sz) -> void {
    mgc_big_copy(dx, sx); mgc_big_copy(dy, sy); mgc_big_copy(dz, sz);
}

fn _secp_mul_small(int* out, int* a, int v, int* p) -> void {
    int* c = alloc<int>(16);
    if (c == null) { return; }
    _secp_small(c, v);
    mgc_big_mod_mul(out, a, c, p);
    free(c);
}

// Jacobian doubling. Safe when x3/y3/z3 alias x1/y1/z1.
fn secp_point_double(int* x3, int* y3, int* z3, int* x1, int* y1, int* z1) -> void {
    if (_secp_point_is_infinity(z1) || mgc_big_is_zero(y1)) {
        _secp_point_infinity(x3, y3, z3);
        return;
    }
    int* p = alloc<int>(16);
    int* A = alloc<int>(16); int* B = alloc<int>(16); int* C = alloc<int>(16);
    int* D = alloc<int>(16); int* E = alloc<int>(16); int* F = alloc<int>(16);
    int* t = alloc<int>(16); int* t2 = alloc<int>(16);
    if (p == null || A == null || B == null || C == null || D == null || E == null || F == null || t == null || t2 == null) {
        _secp_point_infinity(x3, y3, z3); return;
    }
    secp_p(p);

    mgc_big_mod_mul(A, x1, x1, p);               // A = X^2
    mgc_big_mod_mul(B, y1, y1, p);               // B = Y^2
    mgc_big_mod_mul(C, B, B, p);                 // C = B^2
    mgc_big_mod_add(t, x1, B, p);
    mgc_big_mod_mul(D, t, t, p);                 // (X+B)^2
    mgc_big_mod_sub(D, D, A, p);
    mgc_big_mod_sub(D, D, C, p);
    _secp_mul_small(D, D, 2, p);                 // D = 2*((X+B)^2-A-C)

    _secp_mul_small(E, A, 3, p);                 // E = 3*A
    mgc_big_mod_mul(F, E, E, p);                 // F = E^2

    _secp_mul_small(t, D, 2, p);
    mgc_big_mod_sub(t, F, t, p);                 // X3 = F - 2D
    mgc_big_copy(x3, t);

    mgc_big_mod_sub(t, D, x3, p);
    mgc_big_mod_mul(t, E, t, p);
    _secp_mul_small(t2, C, 8, p);
    mgc_big_mod_sub(y3, t, t2, p);               // Y3 = E*(D-X3)-8C

    mgc_big_mod_mul(t, y1, z1, p);
    _secp_mul_small(z3, t, 2, p);                // Z3 = 2*Y*Z

    free(p); free(A); free(B); free(C); free(D); free(E); free(F); free(t); free(t2);
}

// Jacobian addition. Safe when output aliases either input point.
fn secp_point_add(int* x3, int* y3, int* z3, int* x1, int* y1, int* z1, int* x2, int* y2, int* z2) -> void {
    if (_secp_point_is_infinity(z1)) { _secp_copy_point(x3, y3, z3, x2, y2, z2); return; }
    if (_secp_point_is_infinity(z2)) { _secp_copy_point(x3, y3, z3, x1, y1, z1); return; }

    int* p = alloc<int>(16);
    int* Z1Z1 = alloc<int>(16); int* Z2Z2 = alloc<int>(16);
    int* U1 = alloc<int>(16); int* U2 = alloc<int>(16);
    int* S1 = alloc<int>(16); int* S2 = alloc<int>(16);
    int* H = alloc<int>(16); int* R = alloc<int>(16);
    int* HH = alloc<int>(16); int* HHH = alloc<int>(16); int* V = alloc<int>(16);
    int* t = alloc<int>(16); int* t2 = alloc<int>(16);
    if (p == null || Z1Z1 == null || Z2Z2 == null || U1 == null || U2 == null || S1 == null || S2 == null || H == null || R == null || HH == null || HHH == null || V == null || t == null || t2 == null) {
        _secp_point_infinity(x3, y3, z3); return;
    }
    secp_p(p);

    mgc_big_mod_mul(Z1Z1, z1, z1, p);
    mgc_big_mod_mul(Z2Z2, z2, z2, p);
    mgc_big_mod_mul(U1, x1, Z2Z2, p);
    mgc_big_mod_mul(U2, x2, Z1Z1, p);
    mgc_big_mod_mul(t, z2, Z2Z2, p);
    mgc_big_mod_mul(S1, y1, t, p);
    mgc_big_mod_mul(t, z1, Z1Z1, p);
    mgc_big_mod_mul(S2, y2, t, p);
    mgc_big_mod_sub(H, U2, U1, p);
    mgc_big_mod_sub(R, S2, S1, p);

    if (mgc_big_is_zero(H)) {
        if (mgc_big_is_zero(R)) {
            secp_point_double(x3, y3, z3, x1, y1, z1);
        } else {
            _secp_point_infinity(x3, y3, z3);
        }
        free(p); free(Z1Z1); free(Z2Z2); free(U1); free(U2); free(S1); free(S2);
        free(H); free(R); free(HH); free(HHH); free(V); free(t); free(t2);
        return;
    }

    mgc_big_mod_mul(HH, H, H, p);
    mgc_big_mod_mul(HHH, HH, H, p);
    mgc_big_mod_mul(V, U1, HH, p);

    mgc_big_mod_mul(t, R, R, p);
    mgc_big_mod_sub(t, t, HHH, p);
    _secp_mul_small(t2, V, 2, p);
    mgc_big_mod_sub(t, t, t2, p);
    mgc_big_copy(x3, t);                          // X3 = R^2 - HHH - 2V

    mgc_big_mod_sub(t, V, x3, p);
    mgc_big_mod_mul(t, R, t, p);
    mgc_big_mod_mul(t2, S1, HHH, p);
    mgc_big_mod_sub(y3, t, t2, p);                // Y3 = R*(V-X3)-S1*HHH

    mgc_big_mod_mul(t, z1, z2, p);
    mgc_big_mod_mul(z3, t, H, p);                 // Z3 = Z1*Z2*H

    free(p); free(Z1Z1); free(Z2Z2); free(U1); free(U2); free(S1); free(S2);
    free(H); free(R); free(HH); free(HHH); free(V); free(t); free(t2);
}

fn secp_point_to_affine(int* ax, int* ay, int* x, int* y, int* z) -> bool {
    if (ax == null || ay == null || x == null || y == null || z == null) { return false; }
    if (mgc_big_is_zero(z)) { mgc_big_zero(ax); mgc_big_zero(ay); return false; }
    int* p = alloc<int>(16);
    int* zi = alloc<int>(16); int* zi2 = alloc<int>(16); int* zi3 = alloc<int>(16);
    if (p == null || zi == null || zi2 == null || zi3 == null) {
        free(p); free(zi); free(zi2); free(zi3);
        return false;
    }
    secp_p(p);
    if (!mgc_big_mod_inv(zi, z, p)) {
        free(p); free(zi); free(zi2); free(zi3);
        return false;
    }
    mgc_big_mod_mul(zi2, zi, zi, p);
    mgc_big_mod_mul(zi3, zi2, zi, p);
    mgc_big_mod_mul(ax, x, zi2, p);
    mgc_big_mod_mul(ay, y, zi3, p);
    free(p); free(zi); free(zi2); free(zi3);
    return true;
}

fn secp_scalar_mul(int* rx, int* ry, int* rz, int* k, int* px, int* py, int* pz) -> void {
    if (rx == null || ry == null || rz == null || k == null || px == null || py == null || pz == null) { return; }
    int* tx = alloc<int>(16); int* ty = alloc<int>(16); int* tz = alloc<int>(16);
    int* ux = alloc<int>(16); int* uy = alloc<int>(16); int* uz = alloc<int>(16);
    if (tx == null || ty == null || tz == null || ux == null || uy == null || uz == null) {
        free(tx); free(ty); free(tz); free(ux); free(uy); free(uz);
        return;
    }
    _secp_point_infinity(rx, ry, rz);
    int bits = mgc_big_bit_length(k);
    for (int i = bits - 1; i >= 0; i = i - 1) {
        secp_point_double(tx, ty, tz, rx, ry, rz);
        _secp_copy_point(rx, ry, rz, tx, ty, tz);
        if (mgc_big_bit(k, i) != 0) {
            secp_point_add(ux, uy, uz, rx, ry, rz, px, py, pz);
            _secp_copy_point(rx, ry, rz, ux, uy, uz);
        }
    }
    free(tx); free(ty); free(tz); free(ux); free(uy); free(uz);
}

fn secp_generator(int* gx, int* gy, int* gz) -> void {
    secp_gx(gx); secp_gy(gy); _secp_one(gz);
}

// Compressed pubkey: 33 bytes, prefix 02/03, X big-endian.
fn secp_pubkey_from_priv(int* priv, char* out33) -> bool {
    if (priv == null || out33 == null) { return false; }
    int* n = alloc<int>(16);
    int* gx = alloc<int>(16); int* gy = alloc<int>(16); int* gz = alloc<int>(16);
    int* px = alloc<int>(16); int* py = alloc<int>(16); int* pz = alloc<int>(16);
    int* ax = alloc<int>(16); int* ay = alloc<int>(16);
    if (n == null || gx == null || gy == null || gz == null || px == null || py == null || pz == null || ax == null || ay == null) {
        free(n); free(gx); free(gy); free(gz); free(px); free(py); free(pz); free(ax); free(ay);
        return false;
    }
    secp_n(n);
    if (mgc_big_is_zero(priv) || mgc_big_cmp(priv, n) >= 0) {
        free(n); free(gx); free(gy); free(gz); free(px); free(py); free(pz); free(ax); free(ay);
        return false;
    }
    secp_generator(gx, gy, gz);
    secp_scalar_mul(px, py, pz, priv, gx, gy, gz);
    bool ok = secp_point_to_affine(ax, ay, px, py, pz);
    if (ok) {
        if (mgc_big_bit(ay, 0) != 0) { out33[0] = cast<char>(3); }
        else { out33[0] = cast<char>(2); }
        mgc_big_to_bytes_be(ax, out33 + 1);
    }
    free(n); free(gx); free(gy); free(gz); free(px); free(py); free(pz); free(ax); free(ay);
    return ok;
}

fn secp_pubkey_parse(char* pub, int pub_len, int* qx, int* qy, int* qz) -> bool {
    if (pub == null || qx == null || qy == null || qz == null) { return false; }
    int prefix = cast<int>(*(pub + 0)) & 255;
    int* p = alloc<int>(16);
    int* rhs = alloc<int>(16);
    int* t = alloc<int>(16);
    int* exp = alloc<int>(16);
    int* y = alloc<int>(16);
    int* y2 = alloc<int>(16);
    if (p == null || rhs == null || t == null || exp == null || y == null || y2 == null) {
        free(p); free(rhs); free(t); free(exp); free(y); free(y2);
        return false;
    }
    secp_p(p);

    if (prefix == 2 || prefix == 3) {
        if (pub_len != 33) { free(p); free(rhs); free(t); free(exp); free(y); free(y2); return false; }
        mgc_big_from_bytes_be(qx, pub + 1, 32);
        mgc_big_mod_mul(t, qx, qx, p);
        mgc_big_mod_mul(rhs, t, qx, p);
        _secp_small(t, 7);
        mgc_big_mod_add(rhs, rhs, t, p);
        secp_sqrt_exp(exp);
        mgc_big_mod_pow(y, rhs, exp, p);
        mgc_big_mod_mul(y2, y, y, p);
        if (mgc_big_cmp(y2, rhs) != 0) {
            free(p); free(rhs); free(t); free(exp); free(y); free(y2); return false;
        }
        int parity = mgc_big_bit(y, 0);
        bool want_odd = (prefix == 3);
        if ((parity != 0) != want_odd) {
            int* one = alloc<int>(16);
            _secp_one(one);
            mgc_big_sub(y, p, y);
            free(one);
        }
        mgc_big_copy(qy, y);
        _secp_one(qz);
        free(p); free(rhs); free(t); free(exp); free(y); free(y2);
        return true;
    }

    if (prefix == 4) {
        if (pub_len != 65) { free(p); free(rhs); free(t); free(exp); free(y); free(y2); return false; }
        mgc_big_from_bytes_be(qx, pub + 1, 32);
        mgc_big_from_bytes_be(qy, pub + 33, 32);
        _secp_one(qz);
        free(p); free(rhs); free(t); free(exp); free(y); free(y2);
        return true;
    }

    free(p); free(rhs); free(t); free(exp); free(y); free(y2);
    return false;
}

// HMAC-SHA256 with binary key (needed by RFC6979).
fn _secp_hmac(char* key, int key_len, char* msg, int msg_len, char* out32) -> void {
    if (out32 == null) { return; }
    char* block = alloc<char>(64);
    char* inner = alloc<char>(64 + msg_len);
    char* outer = alloc<char>(96);
    char* ih = alloc<char>(32);
    if (block == null || inner == null || outer == null || ih == null) {
        free(block); free(inner); free(outer); free(ih);
        return;
    }
    mgc_zero(block, 64);
    if (key_len > 64) {
        crypto_sha256_raw(key, key_len, block);
    } else if (key_len > 0) {
        mgc_copy(block, key, key_len);
    }
    for (int i = 0; i < 64; i = i + 1) {
        int k = cast<int>(*(block + i)) & 255;
        *(inner + i) = cast<char>(k ^ 54);
        *(outer + i) = cast<char>(k ^ 92);
    }
    if (msg_len > 0) { mgc_copy(inner + 64, msg, msg_len); }
    crypto_sha256_raw(inner, 64 + msg_len, ih);
    mgc_copy(outer + 64, ih, 32);
    crypto_sha256_raw(outer, 96, out32);
    free(block); free(inner); free(outer); free(ih);
}

fn _secp_hmac_cat(char* key, int key_len, char* a, int alen, char* b, int blen, char* out32) -> void {
    char* buf = alloc<char>(alen + blen);
    if (buf == null) { return; }
    if (alen > 0) { mgc_copy(buf, a, alen); }
    if (blen > 0) { mgc_copy(buf + alen, b, blen); }
    _secp_hmac(key, key_len, buf, alen + blen, out32);
    free(buf);
}

fn _secp_build_k(int* out, char* priv32, char* digest32) -> void {
    int* n = alloc<int>(16);
    int* h = alloc<int>(16);
    int* hm = alloc<int>(16);
    if (n == null || h == null || hm == null) { free(n); free(h); free(hm); return; }
    secp_n(n);
    mgc_big_from_bytes_be(h, digest32, 32);
    mgc_big_mod(hm, h, 16, n);
    char* hbytes = alloc<char>(32);
    char* V = alloc<char>(32);
    char* K = alloc<char>(32);
    char* buf = alloc<char>(97);
    char* T = alloc<char>(32);
    if (hbytes == null || V == null || K == null || buf == null || T == null) {
        free(n); free(h); free(hm); free(hbytes); free(V); free(K); free(buf); free(T);
        return;
    }
    mgc_big_to_bytes_be(hm, hbytes);
    mgc_zero(V, 32);
    mgc_zero(K, 32);
    for (int i = 0; i < 32; i = i + 1) { V[i] = cast<char>(1); }

    // K = HMAC(K, V || 0x00 || priv || bits2octets(hash))
    mgc_copy(buf, V, 32);
    buf[32] = cast<char>(0);
    mgc_copy(buf + 33, priv32, 32);
    mgc_copy(buf + 65, hbytes, 32);
    _secp_hmac(K, 32, buf, 97, K);
    _secp_hmac(K, 32, V, 32, V);
    // K = HMAC(K, V || 0x01 || priv || bits2octets(hash))
    mgc_copy(buf, V, 32);
    buf[32] = cast<char>(1);
    mgc_copy(buf + 33, priv32, 32);
    mgc_copy(buf + 65, hbytes, 32);
    _secp_hmac(K, 32, buf, 97, K);
    _secp_hmac(K, 32, V, 32, V);

    int tries = 0;
    while (tries < 1000) {
        _secp_hmac(K, 32, V, 32, T);
        mgc_big_from_bytes_be(out, T, 32);
        if (!mgc_big_is_zero(out) && mgc_big_cmp(out, n) < 0) { break; }
        mgc_copy(buf, V, 32);
        buf[32] = cast<char>(0);
        _secp_hmac(K, 32, buf, 33, K);
        _secp_hmac(K, 32, V, 32, V);
        tries = tries + 1;
    }

    free(n); free(h); free(hm); free(hbytes); free(V); free(K); free(buf); free(T);
}

fn _secp_der_int(int* v, char* out) -> int {
    char* rbuf = alloc<char>(32);
    if (rbuf == null) { return 0; }
    mgc_big_to_bytes_be(v, rbuf);
    int start = 0;
    while (start < 31 && (cast<int>(*(rbuf + start)) & 255) == 0) { start = start + 1; }
    int len = 32 - start;
    int pos = 0;
    if ((cast<int>(*(rbuf + start)) & 0x80) != 0) {
        *(out + pos) = cast<char>(0); pos = pos + 1;
    }
    for (int i = start; i < 32; i = i + 1) {
        *(out + pos) = *(rbuf + i); pos = pos + 1;
    }
    free(rbuf);
    return pos;
}

// DER SEQUENCE { INTEGER r, INTEGER s }.
fn secp_der_encode(int* r, int* s, char* out, int* out_len) -> bool {
    if (r == null || s == null || out == null || out_len == null) { return false; }
    char* rb = alloc<char>(33);
    char* sb = alloc<char>(33);
    if (rb == null || sb == null) { free(rb); free(sb); return false; }
    int rl = _secp_der_int(r, rb);
    int sl = _secp_der_int(s, sb);
    int pos = 0;
    *(out + pos) = cast<char>(0x30); pos = pos + 1;
    *(out + pos) = cast<char>(4 + rl + sl); pos = pos + 1;
    *(out + pos) = cast<char>(0x02); pos = pos + 1;
    *(out + pos) = cast<char>(rl); pos = pos + 1;
    for (int i = 0; i < rl; i = i + 1) { *(out + pos) = *(rb + i); pos = pos + 1; }
    *(out + pos) = cast<char>(0x02); pos = pos + 1;
    *(out + pos) = cast<char>(sl); pos = pos + 1;
    for (int i = 0; i < sl; i = i + 1) { *(out + pos) = *(sb + i); pos = pos + 1; }
    *out_len = pos;
    free(rb); free(sb);
    return true;
}

fn secp_der_decode(char* der, int der_len, int* r, int* s) -> bool {
    if (der == null || der_len < 8 || r == null || s == null) { return false; }
    int pos = 0;
    if ((cast<int>(*(der + pos)) & 255) != 0x30) { return false; }
    pos = pos + 1;
    int seq_len = cast<int>(*(der + pos)) & 255;
    pos = pos + 1;
    if (seq_len >= 0x80 || pos + seq_len != der_len) { return false; }

    if ((cast<int>(*(der + pos)) & 255) != 0x02) { return false; }
    pos = pos + 1;
    int rl = cast<int>(*(der + pos)) & 255;
    pos = pos + 1;
    if (rl <= 0 || rl > 33 || pos + rl > der_len) { return false; }
    int rstart = pos;
    if (rl > 32) {
        if ((cast<int>(*(der + rstart)) & 255) != 0) { return false; }
        rstart = rstart + 1;
        rl = rl - 1;
    }
    char* tmp = alloc<char>(32);
    if (tmp == null) { return false; }
    mgc_zero(tmp, 32);
    mgc_copy(tmp + (32 - rl), der + rstart, rl);
    mgc_big_from_bytes_be(r, tmp, 32);
    pos = pos + rl + (rl < 32 ? 0 : 0);
    // fix cursor based on original length (including optional zero pad)
    pos = rstart + rl;

    if ((cast<int>(*(der + pos)) & 255) != 0x02) { free(tmp); return false; }
    pos = pos + 1;
    int sl = cast<int>(*(der + pos)) & 255;
    pos = pos + 1;
    if (sl <= 0 || sl > 33 || pos + sl > der_len) { free(tmp); return false; }
    int sstart = pos;
    if (sl > 32) {
        if ((cast<int>(*(der + sstart)) & 255) != 0) { free(tmp); return false; }
        sstart = sstart + 1;
        sl = sl - 1;
    }
    mgc_zero(tmp, 32);
    mgc_copy(tmp + (32 - sl), der + sstart, sl);
    mgc_big_from_bytes_be(s, tmp, 32);
    pos = sstart + sl;
    free(tmp);
    return pos == der_len;
}

// Returns DER signature length. Deterministic nonce per RFC6979.
fn secp_ecdsa_sign(char* digest32, char* priv32, char* out_der, int* out_len) -> bool {
    if (digest32 == null || priv32 == null || out_der == null || out_len == null) { return false; }
    int* d = alloc<int>(16);
    int* n = alloc<int>(16);
    int* z = alloc<int>(16);
    int* k = alloc<int>(16);
    int* r = alloc<int>(16);
    int* s = alloc<int>(16);
    int* gx = alloc<int>(16); int* gy = alloc<int>(16); int* gz = alloc<int>(16);
    int* px = alloc<int>(16); int* py = alloc<int>(16); int* pz = alloc<int>(16);
    int* ax = alloc<int>(16); int* ay = alloc<int>(16);
    int* t = alloc<int>(16); int* t2 = alloc<int>(16);
    int* kinv = alloc<int>(16);
    int* nhalf = alloc<int>(16);
    if (d == null || n == null || z == null || k == null || r == null || s == null || gx == null || gy == null || gz == null || px == null || py == null || pz == null || ax == null || ay == null || t == null || t2 == null || kinv == null || nhalf == null) {
        free(d); free(n); free(z); free(k); free(r); free(s); free(gx); free(gy); free(gz);
        free(px); free(py); free(pz); free(ax); free(ay); free(t); free(t2); free(kinv); free(nhalf);
        return false;
    }
    secp_n(n);
    secp_n_half(nhalf);
    mgc_big_from_bytes_be(d, priv32, 32);
    mgc_big_from_bytes_be(t, digest32, 32);
    mgc_big_mod(z, t, 16, n);
    if (mgc_big_is_zero(d) || mgc_big_cmp(d, n) >= 0) {
        free(d); free(n); free(z); free(k); free(r); free(s); free(gx); free(gy); free(gz);
        free(px); free(py); free(pz); free(ax); free(ay); free(t); free(t2); free(kinv); free(nhalf);
        return false;
    }

    _secp_build_k(k, priv32, digest32);
    secp_generator(gx, gy, gz);
    secp_scalar_mul(px, py, pz, k, gx, gy, gz);
    if (!secp_point_to_affine(ax, ay, px, py, pz)) {
        free(d); free(n); free(z); free(k); free(r); free(s); free(gx); free(gy); free(gz);
        free(px); free(py); free(pz); free(ax); free(ay); free(t); free(t2); free(kinv); free(nhalf);
        return false;
    }
    mgc_big_mod(r, ax, 16, n);

    mgc_big_mod_mul(t, r, d, n);
    mgc_big_mod_add(t, t, z, n);
    if (!mgc_big_mod_inv(kinv, k, n)) {
        free(d); free(n); free(z); free(k); free(r); free(s); free(gx); free(gy); free(gz);
        free(px); free(py); free(pz); free(ax); free(ay); free(t); free(t2); free(kinv); free(nhalf);
        return false;
    }
    mgc_big_mod_mul(s, t, kinv, n);
    if (mgc_big_is_zero(r) || mgc_big_is_zero(s)) {
        free(d); free(n); free(z); free(k); free(r); free(s); free(gx); free(gy); free(gz);
        free(px); free(py); free(pz); free(ax); free(ay); free(t); free(t2); free(kinv); free(nhalf);
        return false;
    }
    if (mgc_big_cmp(s, nhalf) > 0) { mgc_big_sub(s, n, s); }

    bool ok = secp_der_encode(r, s, out_der, out_len);
    free(d); free(n); free(z); free(k); free(r); free(s); free(gx); free(gy); free(gz);
    free(px); free(py); free(pz); free(ax); free(ay); free(t); free(t2); free(kinv); free(nhalf);
    return ok;
}

fn secp_ecdsa_verify(char* digest32, char* pub, int pub_len, char* der, int der_len) -> bool {
    if (digest32 == null || pub == null || der == null) { return false; }
    int* n = alloc<int>(16);
    int* z = alloc<int>(16);
    int* r = alloc<int>(16);
    int* s = alloc<int>(16);
    int* w = alloc<int>(16);
    int* u1 = alloc<int>(16);
    int* u2 = alloc<int>(16);
    int* t = alloc<int>(16);
    int* qx = alloc<int>(16); int* qy = alloc<int>(16); int* qz = alloc<int>(16);
    int* gx = alloc<int>(16); int* gy = alloc<int>(16); int* gz = alloc<int>(16);
    int* x1 = alloc<int>(16); int* y1 = alloc<int>(16); int* z1 = alloc<int>(16);
    int* x2 = alloc<int>(16); int* y2 = alloc<int>(16); int* z2 = alloc<int>(16);
    int* px = alloc<int>(16); int* py = alloc<int>(16); int* pz = alloc<int>(16);
    int* ax = alloc<int>(16); int* ay = alloc<int>(16);
    int* nhalf = alloc<int>(16);
    if (n == null || z == null || r == null || s == null || w == null || u1 == null || u2 == null || t == null || qx == null || qy == null || qz == null || gx == null || gy == null || gz == null || x1 == null || y1 == null || z1 == null || x2 == null || y2 == null || z2 == null || px == null || py == null || pz == null || ax == null || ay == null || nhalf == null) {
        free(n); free(z); free(r); free(s); free(w); free(u1); free(u2); free(t);
        free(qx); free(qy); free(qz); free(gx); free(gy); free(gz);
        free(x1); free(y1); free(z1); free(x2); free(y2); free(z2);
        free(px); free(py); free(pz); free(ax); free(ay); free(nhalf);
        return false;
    }
    secp_n(n);
    secp_n_half(nhalf);
    if (!secp_der_decode(der, der_len, r, s)) {
        free(n); free(z); free(r); free(s); free(w); free(u1); free(u2); free(t);
        free(qx); free(qy); free(qz); free(gx); free(gy); free(gz);
        free(x1); free(y1); free(z1); free(x2); free(y2); free(z2);
        free(px); free(py); free(pz); free(ax); free(ay); free(nhalf);
        return false;
    }
    if (mgc_big_is_zero(r) || mgc_big_is_zero(s) || mgc_big_cmp(r, n) >= 0 || mgc_big_cmp(s, n) >= 0 || mgc_big_cmp(s, nhalf) > 0) {
        free(n); free(z); free(r); free(s); free(w); free(u1); free(u2); free(t);
        free(qx); free(qy); free(qz); free(gx); free(gy); free(gz);
        free(x1); free(y1); free(z1); free(x2); free(y2); free(z2);
        free(px); free(py); free(pz); free(ax); free(ay); free(nhalf);
        return false;
    }
    if (!secp_pubkey_parse(pub, pub_len, qx, qy, qz)) {
        free(n); free(z); free(r); free(s); free(w); free(u1); free(u2); free(t);
        free(qx); free(qy); free(qz); free(gx); free(gy); free(gz);
        free(x1); free(y1); free(z1); free(x2); free(y2); free(z2);
        free(px); free(py); free(pz); free(ax); free(ay); free(nhalf);
        return false;
    }

    mgc_big_from_bytes_be(t, digest32, 32);
    mgc_big_mod(z, t, 16, n);
    mgc_big_mod_inv(w, s, n);
    mgc_big_mod_mul(u1, z, w, n);
    mgc_big_mod_mul(u2, r, w, n);

    secp_generator(gx, gy, gz);
    secp_scalar_mul(x1, y1, z1, u1, gx, gy, gz);
    secp_scalar_mul(x2, y2, z2, u2, qx, qy, qz);
    secp_point_add(px, py, pz, x1, y1, z1, x2, y2, z2);
    bool ok = false;
    if (secp_point_to_affine(ax, ay, px, py, pz)) {
        mgc_big_mod(t, ax, 16, n);
        ok = (mgc_big_cmp(t, r) == 0);
    }

    free(n); free(z); free(r); free(s); free(w); free(u1); free(u2); free(t);
    free(qx); free(qy); free(qz); free(gx); free(gy); free(gz);
    free(x1); free(y1); free(z1); free(x2); free(y2); free(z2);
    free(px); free(py); free(pz); free(ax); free(ay); free(nhalf);
    return ok;
}
