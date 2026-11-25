use "util.mg";

// RIPEMD-160 (big-endian hex output via caller). Pure Magnetar implementation.

fn _r160_rol(int x, int n) -> int {
    int v = x & 4294967295;
    int nn = n & 31;
    if (nn == 0) { return v; }
    return ((v << nn) | (v >> (32 - nn))) & 4294967295;
}

fn _r160_f(int j, int x, int y, int z) -> int {
    if (j <= 15) { return x ^ y ^ z; }
    if (j <= 31) { return (x & y) | ((~x) & z); }
    if (j <= 47) { return (x | (~y)) ^ z; }
    if (j <= 63) { return (x & z) | (y & (~z)); }
    return x ^ (y | (~z));
}

fn _r160_K(int j) -> int {
    if (j <= 15) { return 0; }
    if (j <= 31) { return 1518500249; }      // 0x5A827999
    if (j <= 47) { return 1859775393; }      // 0x6ED9EBA1
    if (j <= 63) { return 2400959708; }      // 0x8F1BBCDC
    return 2840853838;                        // 0xA953FD4E
}

fn _r160_Kp(int j) -> int {
    if (j <= 15) { return 1352829926; }      // 0x50A28BE6
    if (j <= 31) { return 1548603684; }      // 0x5C4DD124
    if (j <= 47) { return 1836072691; }      // 0x6D703EF3
    if (j <= 63) { return 2053994217; }      // 0x7A6D76E9
    return 0;
}

fn _r160_r(int j) -> int {
    // 5 groups of 16
    if (j == 0) { return 11; } if (j == 1) { return 14; } if (j == 2) { return 15; } if (j == 3) { return 12; }
    if (j == 4) { return 5; }  if (j == 5) { return 8; }  if (j == 6) { return 7; }  if (j == 7) { return 9; }
    if (j == 8) { return 11; } if (j == 9) { return 13; } if (j == 10) { return 14; } if (j == 11) { return 15; }
    if (j == 12) { return 6; } if (j == 13) { return 7; }  if (j == 14) { return 9; }  if (j == 15) { return 8; }

    if (j == 16) { return 7; } if (j == 17) { return 6; }  if (j == 18) { return 8; }  if (j == 19) { return 13; }
    if (j == 20) { return 11; } if (j == 21) { return 9; } if (j == 22) { return 7; }  if (j == 23) { return 15; }
    if (j == 24) { return 7; } if (j == 25) { return 12; } if (j == 26) { return 15; } if (j == 27) { return 9; }
    if (j == 28) { return 11; } if (j == 29) { return 7; } if (j == 30) { return 13; } if (j == 31) { return 12; }

    if (j == 32) { return 11; } if (j == 33) { return 13; } if (j == 34) { return 6; } if (j == 35) { return 7; }
    if (j == 36) { return 14; } if (j == 37) { return 9; } if (j == 38) { return 13; } if (j == 39) { return 15; }
    if (j == 40) { return 14; } if (j == 41) { return 8; } if (j == 42) { return 13; } if (j == 43) { return 6; }
    if (j == 44) { return 5; } if (j == 45) { return 12; } if (j == 46) { return 7; } if (j == 47) { return 5; }

    if (j == 48) { return 11; } if (j == 49) { return 12; } if (j == 50) { return 14; } if (j == 51) { return 15; }
    if (j == 52) { return 14; } if (j == 53) { return 15; } if (j == 54) { return 9; } if (j == 55) { return 8; }
    if (j == 56) { return 9; } if (j == 57) { return 14; } if (j == 58) { return 5; } if (j == 59) { return 6; }
    if (j == 60) { return 8; } if (j == 61) { return 6; }  if (j == 62) { return 5; }  if (j == 63) { return 12; }

    if (j == 64) { return 9; } if (j == 65) { return 15; } if (j == 66) { return 5; } if (j == 67) { return 11; }
    if (j == 68) { return 6; } if (j == 69) { return 8; }  if (j == 70) { return 13; } if (j == 71) { return 12; }
    if (j == 72) { return 5; } if (j == 73) { return 12; } if (j == 74) { return 13; } if (j == 75) { return 14; }
    if (j == 76) { return 11; } if (j == 77) { return 8; } if (j == 78) { return 5; }  return 6; // 79
}

fn _r160_rp(int j) -> int {
    if (j == 0) { return 8; }  if (j == 1) { return 9; }  if (j == 2) { return 9; }  if (j == 3) { return 11; }
    if (j == 4) { return 13; } if (j == 5) { return 15; } if (j == 6) { return 15; } if (j == 7) { return 5; }
    if (j == 8) { return 7; }  if (j == 9) { return 7; }  if (j == 10) { return 8; } if (j == 11) { return 11; }
    if (j == 12) { return 14; } if (j == 13) { return 14; } if (j == 14) { return 12; } if (j == 15) { return 6; }

    if (j == 16) { return 9; } if (j == 17) { return 13; } if (j == 18) { return 15; } if (j == 19) { return 7; }
    if (j == 20) { return 12; } if (j == 21) { return 8; } if (j == 22) { return 9; }  if (j == 23) { return 11; }
    if (j == 24) { return 7; } if (j == 25) { return 7; }  if (j == 26) { return 12; } if (j == 27) { return 7; }
    if (j == 28) { return 6; } if (j == 29) { return 15; } if (j == 30) { return 13; } if (j == 31) { return 11; }

    if (j == 32) { return 9; } if (j == 33) { return 7; }  if (j == 34) { return 15; } if (j == 35) { return 11; }
    if (j == 36) { return 8; } if (j == 37) { return 6; }  if (j == 38) { return 6; }  if (j == 39) { return 14; }
    if (j == 40) { return 12; } if (j == 41) { return 13; } if (j == 42) { return 5; } if (j == 43) { return 14; }
    if (j == 44) { return 13; } if (j == 45) { return 13; } if (j == 46) { return 7; } if (j == 47) { return 5; }

    if (j == 48) { return 15; } if (j == 49) { return 5; } if (j == 50) { return 8; } if (j == 51) { return 11; }
    if (j == 52) { return 14; } if (j == 53) { return 14; } if (j == 54) { return 6; } if (j == 55) { return 14; }
    if (j == 56) { return 6; } if (j == 57) { return 9; }  if (j == 58) { return 12; } if (j == 59) { return 9; }
    if (j == 60) { return 12; } if (j == 61) { return 5; } if (j == 62) { return 15; } if (j == 63) { return 8; }

    if (j == 64) { return 8; } if (j == 65) { return 5; }  if (j == 66) { return 12; } if (j == 67) { return 9; }
    if (j == 68) { return 12; } if (j == 69) { return 5; } if (j == 70) { return 14; } if (j == 71) { return 6; }
    if (j == 72) { return 8; } if (j == 73) { return 13; } if (j == 74) { return 6; }  if (j == 75) { return 5; }
    if (j == 76) { return 15; } if (j == 77) { return 13; } if (j == 78) { return 11; } return 11; // 79
}

fn _r160_s(int j) -> int {
    if (j == 0) { return 0; }  if (j == 1) { return 1; }  if (j == 2) { return 2; }  if (j == 3) { return 3; }
    if (j == 4) { return 4; }  if (j == 5) { return 5; }  if (j == 6) { return 6; }  if (j == 7) { return 7; }
    if (j == 8) { return 8; }  if (j == 9) { return 9; }  if (j == 10) { return 10; } if (j == 11) { return 11; }
    if (j == 12) { return 12; } if (j == 13) { return 13; } if (j == 14) { return 14; } if (j == 15) { return 15; }

    if (j == 16) { return 7; } if (j == 17) { return 4; }  if (j == 18) { return 13; } if (j == 19) { return 1; }
    if (j == 20) { return 10; } if (j == 21) { return 6; } if (j == 22) { return 15; } if (j == 23) { return 3; }
    if (j == 24) { return 12; } if (j == 25) { return 0; } if (j == 26) { return 9; }  if (j == 27) { return 5; }
    if (j == 28) { return 2; } if (j == 29) { return 14; } if (j == 30) { return 11; } if (j == 31) { return 8; }

    if (j == 32) { return 3; } if (j == 33) { return 10; } if (j == 34) { return 14; } if (j == 35) { return 4; }
    if (j == 36) { return 9; } if (j == 37) { return 15; } if (j == 38) { return 8; }  if (j == 39) { return 1; }
    if (j == 40) { return 2; } if (j == 41) { return 7; }  if (j == 42) { return 0; }  if (j == 43) { return 6; }
    if (j == 44) { return 13; } if (j == 45) { return 11; } if (j == 46) { return 5; } if (j == 47) { return 12; }

    if (j == 48) { return 1; } if (j == 49) { return 9; }  if (j == 50) { return 11; } if (j == 51) { return 10; }
    if (j == 52) { return 0; } if (j == 53) { return 8; }  if (j == 54) { return 12; } if (j == 55) { return 4; }
    if (j == 56) { return 13; } if (j == 57) { return 3; } if (j == 58) { return 7; }  if (j == 59) { return 15; }
    if (j == 60) { return 14; } if (j == 61) { return 5; } if (j == 62) { return 6; }  if (j == 63) { return 2; }

    if (j == 64) { return 4; } if (j == 65) { return 0; }  if (j == 66) { return 5; }  if (j == 67) { return 9; }
    if (j == 68) { return 7; } if (j == 69) { return 12; } if (j == 70) { return 2; }  if (j == 71) { return 10; }
    if (j == 72) { return 14; } if (j == 73) { return 1; } if (j == 74) { return 3; }  if (j == 75) { return 8; }
    if (j == 76) { return 11; } if (j == 77) { return 6; } if (j == 78) { return 15; } return 13; // 79
}

fn _r160_sp(int j) -> int {
    if (j == 0) { return 5; }  if (j == 1) { return 14; } if (j == 2) { return 7; }  if (j == 3) { return 0; }
    if (j == 4) { return 9; }  if (j == 5) { return 2; }  if (j == 6) { return 11; } if (j == 7) { return 4; }
    if (j == 8) { return 13; } if (j == 9) { return 6; }  if (j == 10) { return 15; } if (j == 11) { return 8; }
    if (j == 12) { return 1; } if (j == 13) { return 10; } if (j == 14) { return 3; }  if (j == 15) { return 12; }

    if (j == 16) { return 6; } if (j == 17) { return 11; } if (j == 18) { return 3; }  if (j == 19) { return 7; }
    if (j == 20) { return 0; } if (j == 21) { return 13; } if (j == 22) { return 5; }  if (j == 23) { return 10; }
    if (j == 24) { return 14; } if (j == 25) { return 15; } if (j == 26) { return 8; } if (j == 27) { return 12; }
    if (j == 28) { return 4; } if (j == 29) { return 9; }  if (j == 30) { return 1; }  if (j == 31) { return 2; }

    if (j == 32) { return 15; } if (j == 33) { return 5; } if (j == 34) { return 1; }  if (j == 35) { return 3; }
    if (j == 36) { return 7; } if (j == 37) { return 14; } if (j == 38) { return 6; }  if (j == 39) { return 9; }
    if (j == 40) { return 11; } if (j == 41) { return 8; } if (j == 42) { return 12; } if (j == 43) { return 2; }
    if (j == 44) { return 10; } if (j == 45) { return 0; } if (j == 46) { return 4; }  if (j == 47) { return 13; }

    if (j == 48) { return 8; } if (j == 49) { return 6; }  if (j == 50) { return 4; }  if (j == 51) { return 1; }
    if (j == 52) { return 3; } if (j == 53) { return 11; } if (j == 54) { return 15; } if (j == 55) { return 0; }
    if (j == 56) { return 5; } if (j == 57) { return 12; } if (j == 58) { return 2; }  if (j == 59) { return 13; }
    if (j == 60) { return 9; } if (j == 61) { return 7; }  if (j == 62) { return 10; } if (j == 63) { return 14; }

    if (j == 64) { return 12; } if (j == 65) { return 15; } if (j == 66) { return 10; } if (j == 67) { return 4; }
    if (j == 68) { return 1; } if (j == 69) { return 5; }  if (j == 70) { return 8; }  if (j == 71) { return 7; }
    if (j == 72) { return 6; } if (j == 73) { return 2; }  if (j == 74) { return 13; } if (j == 75) { return 14; }
    if (j == 76) { return 0; } if (j == 77) { return 3; }  if (j == 78) { return 9; }  return 11; // 79
}

fn _r160_put_u32_le(char* out, int offset, int value) -> void {
    int v = value & 4294967295;
    *(out + offset) = cast<char>(v & 255);
    *(out + offset + 1) = cast<char>((v >> 8) & 255);
    *(out + offset + 2) = cast<char>((v >> 16) & 255);
    *(out + offset + 3) = cast<char>((v >> 24) & 255);
}

fn ripemd160_raw(char* data, int length, char* out20) -> void {
    if (out20 == null) { return; }
    mgc_zero(out20, 20);
    if (data == null) { length = 0; }
    if (length < 0) { length = 0; }

    int h0 = 1732584193;  // 0x67452301
    int h1 = 4023233417;  // 0xEFCDAB89
    int h2 = 2562383102;  // 0x98BADCFE
    int h3 = 271733878;   // 0x10325476
    int h4 = 3285377520;  // 0xC3D2E1F0

    int bit_len = length * 8;
    int padded_len = ((length + 9 + 63) / 64) * 64;
    char* msg = alloc<char>(padded_len);
    if (msg == null) { return; }
    mgc_zero(msg, padded_len);
    if (length > 0) { mgc_copy(msg, data, length); }
    *(msg + length) = cast<char>(128);
    _r160_put_u32_le(msg, padded_len - 8, bit_len & 4294967295);
    _r160_put_u32_le(msg, padded_len - 4, 0);

    int* X = alloc<int>(16);
    if (X == null) { free(msg); return; }

    int blocks = padded_len / 64;
    for (int block = 0; block < blocks; block = block + 1) {
        int bbase = block * 64;
        for (int i = 0; i < 16; i = i + 1) {
            int o = bbase + i * 4;
            int b0 = cast<int>(*(msg + o)) & 255;
            int b1 = cast<int>(*(msg + o + 1)) & 255;
            int b2 = cast<int>(*(msg + o + 2)) & 255;
            int b3 = cast<int>(*(msg + o + 3)) & 255;
            X[i] = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
        }

        int A = h0; int B = h1; int C = h2; int D = h3; int E = h4;
        int Ap = h0; int Bp = h1; int Cp = h2; int Dp = h3; int Ep = h4;

        for (int j = 0; j < 80; j = j + 1) {
            int T = (A + _r160_f(j, B, C, D) + X[_r160_s(j)] + _r160_K(j)) & 4294967295;
            T = (_r160_rol(T, _r160_r(j)) + E) & 4294967295;
            A = E; E = D; D = _r160_rol(C, 10); C = B; B = T;

            int jj = 79 - j;
            int Tp = (Ap + _r160_f(jj, Bp, Cp, Dp) + X[_r160_sp(j)] + _r160_Kp(j)) & 4294967295;
            Tp = (_r160_rol(Tp, _r160_rp(j)) + Ep) & 4294967295;
            Ap = Ep; Ep = Dp; Dp = _r160_rol(Cp, 10); Cp = Bp; Bp = Tp;
        }

        int Tt = (h1 + C + Dp) & 4294967295;
        h1 = (h2 + D + Ep) & 4294967295;
        h2 = (h3 + E + Ap) & 4294967295;
        h3 = (h4 + A + Bp) & 4294967295;
        h4 = (h0 + B + Cp) & 4294967295;
        h0 = Tt;
    }

    _r160_put_u32_le(out20, 0, h0);
    _r160_put_u32_le(out20, 4, h1);
    _r160_put_u32_le(out20, 8, h2);
    _r160_put_u32_le(out20, 12, h3);
    _r160_put_u32_le(out20, 16, h4);

    free(X);
    free(msg);
}
