// Magnetar Coin — minimal script templates and P2PKH scriptSig parsing.

use "util.mg";

fn mgc_script_p2pkh(char* h160, char* out25) -> void {
    if (h160 == null || out25 == null) { return; }
    *(out25 + 0) = cast<char>(0x76);
    *(out25 + 1) = cast<char>(0xa9);
    *(out25 + 2) = cast<char>(0x14);
    mgc_copy(out25 + 3, h160, 20);
    *(out25 + 23) = cast<char>(0x88);
    *(out25 + 24) = cast<char>(0xac);
}

fn mgc_script_is_p2pkh(char* script, int len) -> bool {
    if (script == null || len != 25) { return false; }
    if ((cast<int>(*(script + 0)) & 255) != 0x76) { return false; }
    if ((cast<int>(*(script + 1)) & 255) != 0xa9) { return false; }
    if ((cast<int>(*(script + 2)) & 255) != 0x14) { return false; }
    if ((cast<int>(*(script + 23)) & 255) != 0x88) { return false; }
    if ((cast<int>(*(script + 24)) & 255) != 0xac) { return false; }
    return true;
}

fn mgc_script_p2pkh_hash160(char* script, int len, char* out20) -> bool {
    if (out20 == null || !mgc_script_is_p2pkh(script, len)) { return false; }
    mgc_copy(out20, script + 3, 20);
    return true;
}

fn _mgc_script_push_size(int len) -> int {
    if (len < 0 || len > 255) { return -1; }
    if (len == 0) { return 0; }
    if (len < 76) { return 1 + len; }
    return 2 + len;
}

fn _mgc_script_write_push(char* data, int len, char* out, int offset) -> bool {
    if (out == null || offset < 0 || len < 0 || len > 255) { return false; }
    if (len > 0 && data == null) { return false; }
    if (len == 0) { return true; }
    if (len < 76) {
        *(out + offset) = cast<char>(len);
        mgc_copy(out + offset + 1, data, len);
        return true;
    }
    *(out + offset) = cast<char>(0x4c);
    *(out + offset + 1) = cast<char>(len);
    mgc_copy(out + offset + 2, data, len);
    return true;
}

fn mgc_script_push(char* data, int len, char* out, int* out_len) -> bool {
    if (out == null || out_len == null) { return false; }
    int size = _mgc_script_push_size(len);
    if (size < 0) { return false; }
    if (!_mgc_script_write_push(data, len, out, 0)) { return false; }
    *out_len = size;
    return true;
}

fn mgc_script_coinbase(char* data, int len, char* out, int* out_len) -> bool {
    return mgc_script_push(data, len, out, out_len);
}

fn mgc_script_sig(char* sig, int sig_len, char* pub, int pub_len, char* out, int* out_len) -> bool {
    if (out == null || out_len == null) { return false; }
    int first = _mgc_script_push_size(sig_len);
    int second = _mgc_script_push_size(pub_len);
    if (first < 0 || second < 0) { return false; }
    if (!_mgc_script_write_push(sig, sig_len, out, 0)) { return false; }
    if (!_mgc_script_write_push(pub, pub_len, out, first)) { return false; }
    *out_len = first + second;
    return true;
}

fn _mgc_script_read_push(char* script, int len, int offset, char** data, int* data_len, int* next) -> bool {
    if (script == null || data == null || data_len == null || next == null) { return false; }
    if (offset < 0 || offset >= len) { return false; }
    int pos = offset;
    int first = cast<int>(*(script + pos)) & 255;
    pos = pos + 1;
    int count = 0;
    if (first == 0) {
        count = 0;
    } else if (first < 76) {
        count = first;
    } else if (first == 0x4c) {
        if (pos + 1 > len) { return false; }
        count = cast<int>(*(script + pos)) & 255;
        if (count < 76) { return false; }
        pos = pos + 1;
    } else {
        return false;
    }
    if (pos + count > len) { return false; }
    *data = script + pos;
    *data_len = count;
    *next = pos + count;
    return true;
}

fn mgc_script_parse_p2pkh_sig(char* script, int len, char** sig, int* sig_len,
                              char** pub, int* pub_len) -> bool {
    if (sig != null) { *sig = null; }
    if (sig_len != null) { *sig_len = 0; }
    if (pub != null) { *pub = null; }
    if (pub_len != null) { *pub_len = 0; }
    if (script == null || len <= 0 || sig == null || sig_len == null ||
        pub == null || pub_len == null) { return false; }

    char* first_data = null;
    int first_len = 0;
    int next = 0;
    if (!_mgc_script_read_push(script, len, 0, &first_data, &first_len, &next)) { return false; }
    if (first_len <= 0) { return false; }

    char* second_data = null;
    int second_len = 0;
    int end = 0;
    if (!_mgc_script_read_push(script, len, next, &second_data, &second_len, &end)) { return false; }
    if (second_len != 33 || end != len) { return false; }

    *sig = first_data;
    *sig_len = first_len;
    *pub = second_data;
    *pub_len = second_len;
    return true;
}
