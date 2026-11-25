use "../lib/params.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;

    check_int("chain main", mgc_chain_id(MGC_NETWORK_MAIN), 1296515841, &failures);
    check_int("chain test", mgc_chain_id(MGC_NETWORK_TEST), 1296515842, &failures);
    check_int("chain regtest", mgc_chain_id(MGC_NETWORK_REGTEST), 1296515843, &failures);

    check_int("port main", mgc_default_port(MGC_NETWORK_MAIN), 9333, &failures);
    check_int("port test", mgc_default_port(MGC_NETWORK_TEST), 19333, &failures);
    check_int("port regtest", mgc_default_port(MGC_NETWORK_REGTEST), 29333, &failures);

    check_int("rpc regtest", mgc_default_rpc_port(MGC_NETWORK_REGTEST), 29332, &failures);
    check_int("magic main", mgc_p2p_magic(MGC_NETWORK_MAIN), 1296515889, &failures);
    check_int("magic test", mgc_p2p_magic(MGC_NETWORK_TEST), 1296520259, &failures);
    check_int("magic regtest", mgc_p2p_magic(MGC_NETWORK_REGTEST), 1296519747, &failures);

    check_int("addr main", mgc_address_prefix(MGC_NETWORK_MAIN), 50, &failures);
    check_int("addr test", mgc_address_prefix(MGC_NETWORK_TEST), 111, &failures);
    check_int("wif main", mgc_wif_prefix(MGC_NETWORK_MAIN), 128, &failures);
    check_int("wif test", mgc_wif_prefix(MGC_NETWORK_TEST), 239, &failures);

    check_int("interval main", mgc_block_interval(MGC_NETWORK_MAIN), 600, &failures);
    check_int("interval regtest", mgc_block_interval(MGC_NETWORK_REGTEST), 1, &failures);
    check_int("retarget main", mgc_retarget_interval(MGC_NETWORK_MAIN), 2016, &failures);
    check_int("halving main", mgc_halving_interval(MGC_NETWORK_MAIN), 210000, &failures);
    check_int("maturity main", mgc_coinbase_maturity(MGC_NETWORK_MAIN), 100, &failures);
    check_int("bits main", mgc_genesis_bits(MGC_NETWORK_MAIN), 486604799, &failures);
    check_int("bits test", mgc_genesis_bits(MGC_NETWORK_TEST), 520159231, &failures);
    check_int("bits regtest", mgc_genesis_bits(MGC_NETWORK_REGTEST), 545259519, &failures);

    check_int("subsidy", mgc_initial_subsidy(), 5000000000, &failures);
    check_int("max money", mgc_max_money(), 2100000000000000, &failures);
    check_int("max block", MGC_MAX_BLOCK_BYTES, 1000000, &failures);

    return test_report("test_params", failures);
}
