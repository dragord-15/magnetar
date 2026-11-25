// Magnetar Coin — frozen network parameters.
// These values are consensus-critical. Changing any of them after Genesis
// creates a different network.

const int MGC_CHAIN_ID_MAIN    = 1296515841; // 0x4D474301
const int MGC_CHAIN_ID_TEST    = 1296515842; // 0x4D474302
const int MGC_CHAIN_ID_REGTEST = 1296515843; // 0x4D474303

const int MGC_NETWORK_MAIN    = 0;
const int MGC_NETWORK_TEST    = 1;
const int MGC_NETWORK_REGTEST = 2;

const int MGC_PORT_MAIN    = 9333;
const int MGC_PORT_TEST    = 19333;
const int MGC_PORT_REGTEST = 29333;

const int MGC_RPC_PORT_MAIN    = 9332;
const int MGC_RPC_PORT_TEST    = 19332;
const int MGC_RPC_PORT_REGTEST = 29332;

const int MGC_P2P_MAGIC_MAIN    = 1296515889; // 0x4D474331 'MGC1'
const int MGC_P2P_MAGIC_TEST    = 1296520259; // 0x4D475443 'MGCT'
const int MGC_P2P_MAGIC_REGTEST = 1296519747; // 0x4D475243 'MGCR'

const int MGC_ADDRESS_PREFIX_MAIN    = 50;   // 0x32
const int MGC_ADDRESS_PREFIX_TEST    = 111;  // 0x6F
const int MGC_ADDRESS_PREFIX_REGTEST = 111;  // 0x6F

const int MGC_WIF_PREFIX_MAIN    = 128; // 0x80
const int MGC_WIF_PREFIX_TEST    = 239; // 0xEF
const int MGC_WIF_PREFIX_REGTEST = 239; // 0xEF

const int MGC_BLOCK_INTERVAL_MAIN    = 600;
const int MGC_BLOCK_INTERVAL_TEST    = 120;
const int MGC_BLOCK_INTERVAL_REGTEST = 1;

const int MGC_RETARGET_INTERVAL_MAIN    = 2016;
const int MGC_RETARGET_INTERVAL_TEST    = 2016;
const int MGC_RETARGET_INTERVAL_REGTEST = 144;

const int MGC_HALVING_INTERVAL_MAIN    = 210000;
const int MGC_HALVING_INTERVAL_TEST    = 210000;
const int MGC_HALVING_INTERVAL_REGTEST = 150;

// NOTE: v3.5 truncates global `const int` initializers above 2^31-1.
// Keep large money values in functions that return 64-bit literals.
fn mgc_initial_subsidy() -> int { return 5000000000; }       // 50 MGC
fn mgc_max_money() -> int { return 2100000000000000; }       // 21,000,000 MGC

const int MGC_COINBASE_MATURITY_MAIN    = 100;
const int MGC_COINBASE_MATURITY_TEST    = 100;
const int MGC_COINBASE_MATURITY_REGTEST = 10;

const int MGC_MAX_BLOCK_BYTES = 1000000;
const int MGC_MAX_TX_BYTES    = 100000;
const int MGC_MAX_REORG_DEPTH = 288;

const int MGC_GENESIS_BITS_MAIN    = 486604799;  // 0x1D00FFFF
const int MGC_GENESIS_BITS_TEST    = 520159231;  // 0x1F00FFFF
const int MGC_GENESIS_BITS_REGTEST = 545259519;  // 0x207FFFFF

// Frozen after the v0 transaction-id fix. Any change here is a new network.
fn mgc_genesis_hash(int network) -> string {
    if (network == MGC_NETWORK_MAIN) {
        return "83d7204153ca279257d1cfa96109380f6670f4aff435da80b9c7c3cecec1cb9d";
    }
    if (network == MGC_NETWORK_TEST) {
        return "c8914c574ef915949eb25b41261727090d27075db487b0dae615f5af54d2ef31";
    }
    return "5e984494eed2ca8adf2a4548eabea8fabf5b4a1edd4d1c5551464ed62019df92";
}

fn mgc_chain_id(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_CHAIN_ID_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_CHAIN_ID_TEST; }
    return MGC_CHAIN_ID_REGTEST;
}

fn mgc_default_port(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_PORT_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_PORT_TEST; }
    return MGC_PORT_REGTEST;
}

fn mgc_default_rpc_port(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_RPC_PORT_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_RPC_PORT_TEST; }
    return MGC_RPC_PORT_REGTEST;
}

fn mgc_p2p_magic(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_P2P_MAGIC_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_P2P_MAGIC_TEST; }
    return MGC_P2P_MAGIC_REGTEST;
}

fn mgc_address_prefix(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_ADDRESS_PREFIX_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_ADDRESS_PREFIX_TEST; }
    return MGC_ADDRESS_PREFIX_REGTEST;
}

fn mgc_wif_prefix(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_WIF_PREFIX_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_WIF_PREFIX_TEST; }
    return MGC_WIF_PREFIX_REGTEST;
}

fn mgc_block_interval(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_BLOCK_INTERVAL_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_BLOCK_INTERVAL_TEST; }
    return MGC_BLOCK_INTERVAL_REGTEST;
}

fn mgc_retarget_interval(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_RETARGET_INTERVAL_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_RETARGET_INTERVAL_TEST; }
    return MGC_RETARGET_INTERVAL_REGTEST;
}

fn mgc_halving_interval(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_HALVING_INTERVAL_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_HALVING_INTERVAL_TEST; }
    return MGC_HALVING_INTERVAL_REGTEST;
}

fn mgc_coinbase_maturity(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_COINBASE_MATURITY_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_COINBASE_MATURITY_TEST; }
    return MGC_COINBASE_MATURITY_REGTEST;
}

fn mgc_genesis_bits(int network) -> int {
    if (network == MGC_NETWORK_MAIN) { return MGC_GENESIS_BITS_MAIN; }
    if (network == MGC_NETWORK_TEST) { return MGC_GENESIS_BITS_TEST; }
    return MGC_GENESIS_BITS_REGTEST;
}
