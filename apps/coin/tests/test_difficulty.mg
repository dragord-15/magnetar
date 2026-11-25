// Difficulty simulation: 10,000 retarget windows with fast/slow/normal spans.

use "../lib/pow.mg";
use "test_common.mg";

fn _mgc_diff_network(int network, int failures) -> int {
    int interval = mgc_retarget_interval(network);
    int bits = mgc_genesis_bits(network);
    int* target = alloc<int>(16);
    int* maximum = alloc<int>(16);
    if (target == null || maximum == null) {
        if (target != null) { free(target); }
        if (maximum != null) { free(maximum); }
        print_str("FAIL alloc\n");
        return failures + 1;
    }
    mgc_pow_max_target(network, maximum);
    int changes = 0;
    int windows = 10000 / interval;
    for (int i = 0; i < windows; i = i + 1) {
        int height = (i + 1) * interval;
        int span = interval;
        if ((i % 7) == 0) { span = 1; }
        else if ((i % 11) == 0) { span = interval * 8; }
        int next = mgc_pow_next_bits(network, height, bits, span);
        check_bool("retarget target valid", mgc_pow_target_from_bits(next, target), true, &failures);
        check_bool("retarget under maximum", mgc_big_cmp(target, maximum) <= 0, true, &failures);
        if (next != bits) { changes = changes + 1; }
        bits = next;
    }
    check_bool("difficulty changed", changes > 0, true, &failures);
    check_bool("final target valid", mgc_pow_target_from_bits(bits, target), true, &failures);
    free(maximum);
    free(target);
    return failures;
}

fn main() -> int {
    int failures = 0;
    failures = _mgc_diff_network(MGC_NETWORK_REGTEST, failures);
    failures = _mgc_diff_network(MGC_NETWORK_TEST, failures);
    failures = _mgc_diff_network(MGC_NETWORK_MAIN, failures);
    return test_report("test_difficulty", failures);
}
