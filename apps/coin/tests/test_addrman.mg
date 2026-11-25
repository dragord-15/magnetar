// Phase 5A address manager tests.

use "../lib/addrman.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    string path = "/tmp/mgc_addrman_test.txt";

    MgcAddrMan a;
    check_bool("init", mgc_addrman_init(&a, 4), true, &failures);
    check_bool("add first", mgc_addrman_add(&a, 127, 0, 0, 1, 9333), true, &failures);
    check_bool("add second", mgc_addrman_add(&a, 192, 168, 1, 20, 29333), true, &failures);
    check_bool("duplicate rejected", mgc_addrman_add(&a, 127, 0, 0, 1, 9333), false, &failures);
    check_bool("different port accepted", mgc_addrman_add(&a, 127, 0, 0, 1, 9334), true, &failures);
    check_bool("invalid octet rejected", mgc_addrman_add(&a, 256, 0, 0, 1, 9333), false, &failures);
    check_int("count", mgc_addrman_count(&a), 3, &failures);
    check_bool("has first", mgc_addrman_has(&a, 127, 0, 0, 1, 9333), true, &failures);
    check_bool("missing entry", mgc_addrman_has(&a, 10, 0, 0, 1, 9333), false, &failures);

    MgcAddrEntry* e = mgc_addrman_get(&a, 0);
    if (e == null) {
        check_bool("get first", false, true, &failures);
    } else {
        check_int("entry ip0", e.ip0, 127, &failures);
        check_int("entry port", e.port, 9333, &failures);
        check_int("entry attempts", e.attempts, 0, &failures);
        free(e);
    }
    check_bool("get out of range", mgc_addrman_get(&a, 9) != null, false, &failures);

    check_bool("save", mgc_addrman_save(&a, path), true, &failures);

    MgcAddrMan b;
    check_bool("init loaded", mgc_addrman_init(&b, 8), true, &failures);
    check_bool("missing file load", mgc_addrman_load(&b, "/tmp/mgc_addrman_missing_file.txt"), true, &failures);
    check_int("missing file count", mgc_addrman_count(&b), 0, &failures);
    check_bool("load", mgc_addrman_load(&b, path), true, &failures);
    check_int("loaded count", mgc_addrman_count(&b), 3, &failures);
    check_bool("loaded first", mgc_addrman_has(&b, 127, 0, 0, 1, 9333), true, &failures);
    check_bool("loaded second", mgc_addrman_has(&b, 192, 168, 1, 20, 29333), true, &failures);
    check_bool("loaded third", mgc_addrman_has(&b, 127, 0, 0, 1, 9334), true, &failures);
    check_bool("loaded duplicate rejected", mgc_addrman_add(&b, 127, 0, 0, 1, 9333), false, &failures);

    mgc_addrman_free(&b);
    mgc_addrman_free(&a);
    return test_report("test_addrman", failures);
}
