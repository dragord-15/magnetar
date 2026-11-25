// Magnetar Coin — P2P message framing and payload helpers.

use "serialization.mg";
use "hash.mg";
use "util.mg";
use "endian.mg";

const int MGC_P2P_MAX_PAYLOAD = 4000000;
const int MGC_P2P_HEADER_SIZE = 24;
const int MGC_INV_TX = 1;
const int MGC_INV_BLOCK = 2;

struct MgcMsg { char* command; int command_len; char* payload; int payload_len; }

fn mgc_msg_init(MgcMsg* m) -> void {
    if (m == null) { return; }
    m.command = null;
    m.command_len = 0;
    m.payload = null;
    m.payload_len = 0;
}

fn mgc_msg_free(MgcMsg* m) -> void {
    if (m == null) { return; }
    if (m.command != null) {
        free(m.command);
        m.command = null;
    }
    if (m.payload != null) {
        free(m.payload);
        m.payload = null;
    }
    m.command_len = 0;
    m.payload_len = 0;
}

fn mgc_p2p_frame(int magic, string command, char* payload, int payload_len, int* out_len) -> char* {
    if (out_len == null) { return null; }
    *out_len = 0;
    if (command == null || payload_len < 0 || payload_len > MGC_P2P_MAX_PAYLOAD) { return null; }
    if (payload_len > 0 && payload == null) { return null; }
    int cmd_len = len(command);
    if (cmd_len < 0 || cmd_len > 12) { return null; }

    int total = MGC_P2P_HEADER_SIZE + payload_len;
    char* out = alloc<char>(total);
    if (out == null) { return null; }
    mgc_zero(out, total);

    endian_write_u32_le(out, 0, magic);
    mgc_copy(out + 4, cast<char*>(command), cmd_len);
    endian_write_u32_le(out, 16, payload_len);

    char* digest = alloc<char>(32);
    if (digest == null) {
        free(out);
        return null;
    }
    mgc_sha256d_raw(payload, payload_len, digest);
    mgc_copy(out + 20, digest, 4);
    free(digest);

    if (payload_len > 0) { mgc_copy(out + 24, payload, payload_len); }
    *out_len = total;
    return out;
}

fn mgc_p2p_parse(char* data, int len, int magic, MgcMsg* out) -> bool {
    if (out == null) { return false; }
    mgc_msg_init(out);
    if (data == null || len < MGC_P2P_HEADER_SIZE) { return false; }
    if (endian_read_u32_le(data, 0) != magic) { return false; }

    int payload_len = endian_read_u32_le(data, 16);
    if (payload_len < 0 || payload_len > MGC_P2P_MAX_PAYLOAD) { return false; }
    if (len != MGC_P2P_HEADER_SIZE + payload_len) { return false; }

    char* digest = alloc<char>(32);
    if (digest == null) { return false; }
    mgc_sha256d_raw(data + MGC_P2P_HEADER_SIZE, payload_len, digest);
    bool checksum_ok = mgc_equal(digest, data + 20, 4);
    free(digest);
    if (!checksum_ok) { return false; }

    int cmd_len = 0;
    char* cmd_bytes = data + 4;
    while (cmd_len < 12 && *(cmd_bytes + cmd_len) != 0) { cmd_len = cmd_len + 1; }
    char* cmd = alloc<char>(cmd_len + 1);
    if (cmd == null) { return false; }
    mgc_copy(cmd, data + 4, cmd_len);
    *(cmd + cmd_len) = 0;

    int alloc_len = payload_len;
    if (alloc_len < 1) { alloc_len = 1; }
    char* payload_copy = alloc<char>(alloc_len);
    if (payload_copy == null) {
        free(cmd);
        return false;
    }
    mgc_zero(payload_copy, alloc_len);
    if (payload_len > 0) { mgc_copy(payload_copy, data + MGC_P2P_HEADER_SIZE, payload_len); }

    out.command = cmd;
    out.command_len = cmd_len;
    out.payload = payload_copy;
    out.payload_len = payload_len;
    return true;
}

fn mgc_p2p_is(MgcMsg* m, string command) -> bool {
    if (m == null || m.command == null || command == null) { return false; }
    int n = len(command);
    if (n < 0 || n != m.command_len) { return false; }
    return mgc_equal(m.command, cast<char*>(command), n);
}

fn mgc_p2p_write_inv(ByteWriter* w, int type, char* hash32) -> bool {
    if (w == null || !w.ok || hash32 == null) { return false; }
    if (type < 0 || type > 255) { return false; }
    if (!bw_write_varint(w, 1)) { return false; }
    if (!bw_write_u8(w, type)) { return false; }
    return bw_write_bytes(w, hash32, 32);
}

fn mgc_p2p_read_inv(MgcMsg* m, int* type, char* hash32) -> bool {
    if (m == null || m.payload == null || type == null || hash32 == null) { return false; }
    ByteReader r;
    br_init(&r, m.payload, m.payload_len);
    int count = br_read_varint(&r);
    if (!r.ok || count != 1) { return false; }
    int t = br_read_u8(&r);
    if (!r.ok) { return false; }
    if (!br_read_bytes(&r, hash32, 32)) { return false; }
    if (br_remaining(&r) != 0) { return false; }
    *type = t;
    return true;
}

fn mgc_p2p_write_version(ByteWriter* w, int chain_id, int height, int nonce, int port) -> bool {
    if (w == null || !w.ok) { return false; }
    if (chain_id < 0 || height < 0 || nonce < 0 || port < 0) { return false; }
    if (!bw_write_u32(w, chain_id)) { return false; }
    if (!bw_write_u32(w, height)) { return false; }
    if (!bw_write_u32(w, nonce)) { return false; }
    return bw_write_u32(w, port);
}

fn mgc_p2p_read_version(MgcMsg* m, int* chain_id, int* height, int* nonce, int* port) -> bool {
    if (m == null || m.payload == null || chain_id == null || height == null ||
        nonce == null || port == null) { return false; }
    ByteReader r;
    br_init(&r, m.payload, m.payload_len);
    int c = br_read_u32(&r);
    int h = br_read_u32(&r);
    int n = br_read_u32(&r);
    int p = br_read_u32(&r);
    if (!r.ok || br_remaining(&r) != 0) { return false; }
    *chain_id = c;
    *height = h;
    *nonce = n;
    *port = p;
    return true;
}

fn mgc_p2p_write_hashes(ByteWriter* w, char* hashes, int count) -> bool {
    if (w == null || !w.ok || count < 0 || count > MGC_P2P_MAX_PAYLOAD / 32) { return false; }
    if (count > 0 && hashes == null) { return false; }
    if (!bw_write_varint(w, count)) { return false; }
    return bw_write_bytes(w, hashes, count * 32);
}

fn mgc_p2p_read_hashes(MgcMsg* m, char* hashes, int max_count, int* count) -> bool {
    if (m == null || m.payload == null || hashes == null || count == null || max_count < 0) { return false; }
    ByteReader r;
    br_init(&r, m.payload, m.payload_len);
    int n = br_read_varint(&r);
    if (!r.ok || n < 0 || n > MGC_P2P_MAX_PAYLOAD / 32 || n > max_count) { return false; }
    if (n > 0 && !br_read_bytes(&r, hashes, n * 32)) { return false; }
    if (br_remaining(&r) != 0) { return false; }
    *count = n;
    return true;
}
