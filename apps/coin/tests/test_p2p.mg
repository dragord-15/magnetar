// Phase 5A P2P framing tests.

use "../lib/p2p.mg";
use "../lib/params.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    int magic = MGC_P2P_MAGIC_REGTEST;
    int chain = mgc_chain_id(MGC_NETWORK_REGTEST);

    ByteWriter vw;
    bw_init(&vw, 64);
    check_bool("write version", mgc_p2p_write_version(&vw, chain, 7, 12345, 29333), true, &failures);
    check_int("version payload len", vw.length, 16, &failures);

    int frame_len = 0;
    char* frame = mgc_p2p_frame(magic, "version", vw.data, vw.length, &frame_len);
    if (frame == null) {
        print_str("FAIL frame allocation\n");
        return 1;
    }
    check_int("frame len", frame_len, MGC_P2P_HEADER_SIZE + 16, &failures);
    check_int("frame magic", endian_read_u32_le(frame, 0), magic, &failures);
    check_int("frame command first", cast<int>(*(frame + 4)), 118, &failures);
    check_int("frame command pad", cast<int>(*(frame + 11)), 0, &failures);
    check_int("frame payload len field", endian_read_u32_le(frame, 16), 16, &failures);

    char* digest = alloc<char>(32);
    if (digest == null) { print_str("FAIL digest allocation\n"); return 1; }
    mgc_sha256d_raw(vw.data, vw.length, digest);
    check_bool("frame checksum", mgc_equal(digest, frame + 20, 4), true, &failures);

    MgcMsg msg;
    check_bool("parse version", mgc_p2p_parse(frame, frame_len, magic, &msg), true, &failures);
    check_bool("is version", mgc_p2p_is(&msg, "version"), true, &failures);
    check_bool("not inv", mgc_p2p_is(&msg, "inv"), false, &failures);
    check_int("parsed command len", msg.command_len, 7, &failures);
    check_int("parsed payload len", msg.payload_len, 16, &failures);

    int got_chain = 0;
    int got_height = 0;
    int got_nonce = 0;
    int got_port = 0;
    check_bool("read version", mgc_p2p_read_version(&msg, &got_chain, &got_height, &got_nonce, &got_port), true, &failures);
    check_int("version chain", got_chain, chain, &failures);
    check_int("version height", got_height, 7, &failures);
    check_int("version nonce", got_nonce, 12345, &failures);
    check_int("version port", got_port, 29333, &failures);
    mgc_msg_free(&msg);

    check_bool("wrong magic", mgc_p2p_parse(frame, frame_len, MGC_P2P_MAGIC_MAIN, &msg), false, &failures);
    check_bool("truncated frame", mgc_p2p_parse(frame, frame_len - 1, magic, &msg), false, &failures);

    char* bad = alloc<char>(frame_len);
    if (bad == null) { print_str("FAIL bad frame allocation\n"); return 1; }
    mgc_copy(bad, frame, frame_len);
    *(bad + 20) = *(bad + 20) + 1;
    check_bool("bad checksum", mgc_p2p_parse(bad, frame_len, magic, &msg), false, &failures);
    *(bad + 20) = *(bad + 20) - 1;
    endian_write_u32_le(bad, 16, MGC_P2P_MAX_PAYLOAD + 1);
    check_bool("oversized payload", mgc_p2p_parse(bad, frame_len, magic, &msg), false, &failures);
    free(bad);

    char* hash32 = alloc<char>(32);
    if (hash32 == null) { print_str("FAIL hash allocation\n"); return 1; }
    for (int i = 0; i < 32; i = i + 1) { *(hash32 + i) = cast<char>(i + 1); }

    ByteWriter iw;
    bw_init(&iw, 64);
    check_bool("write inv", mgc_p2p_write_inv(&iw, MGC_INV_BLOCK, hash32), true, &failures);
    check_int("inv payload len", iw.length, 34, &failures);
    int inv_frame_len = 0;
    char* inv_frame = mgc_p2p_frame(magic, "inv", iw.data, iw.length, &inv_frame_len);
    if (inv_frame == null) { print_str("FAIL inv frame allocation\n"); return 1; }
    check_bool("parse inv", mgc_p2p_parse(inv_frame, inv_frame_len, magic, &msg), true, &failures);
    check_bool("is inv", mgc_p2p_is(&msg, "inv"), true, &failures);
    int inv_type = 0;
    char* inv_hash = alloc<char>(32);
    if (inv_hash == null) { print_str("FAIL inv hash allocation\n"); return 1; }
    check_bool("read inv", mgc_p2p_read_inv(&msg, &inv_type, inv_hash), true, &failures);
    check_int("inv type", inv_type, MGC_INV_BLOCK, &failures);
    check_bool("inv hash", mgc_equal(inv_hash, hash32, 32), true, &failures);
    mgc_msg_free(&msg);

    char* hashes = alloc<char>(64);
    if (hashes == null) { print_str("FAIL hashes allocation\n"); return 1; }
    mgc_copy(hashes, hash32, 32);
    mgc_copy(hashes + 32, hash32, 32);
    ByteWriter hw;
    bw_init(&hw, 128);
    check_bool("write hashes", mgc_p2p_write_hashes(&hw, hashes, 2), true, &failures);
    int hf_len = 0;
    char* hf = mgc_p2p_frame(magic, "getdata", hw.data, hw.length, &hf_len);
    if (hf == null) { print_str("FAIL getdata frame allocation\n"); return 1; }
    check_bool("parse getdata", mgc_p2p_parse(hf, hf_len, magic, &msg), true, &failures);
    char* hashes_out = alloc<char>(64);
    int hashes_count = 0;
    if (hashes_out == null) { print_str("FAIL hashes out allocation\n"); return 1; }
    check_bool("read hashes", mgc_p2p_read_hashes(&msg, hashes_out, 4, &hashes_count), true, &failures);
    check_int("hashes count", hashes_count, 2, &failures);
    check_bool("hashes bytes", mgc_equal(hashes_out, hashes, 64), true, &failures);
    check_bool("read hashes bound", mgc_p2p_read_hashes(&msg, hashes_out, 1, &hashes_count), false, &failures);
    mgc_msg_free(&msg);

    free(hashes_out);
    free(hf);
    free(hashes);
    free(inv_hash);
    free(inv_frame);
    free(hash32);
    free(digest);
    free(frame);
    bw_free(&hw);
    bw_free(&iw);
    bw_free(&vw);
    return test_report("test_p2p", failures);
}
