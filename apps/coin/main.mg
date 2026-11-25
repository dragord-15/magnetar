// MGC node entry point: single-threaded RPC + P2P event loop.

use "lib/node.mg";
use "lib/rpc.mg";
use "lib/cli.mg";

extern fn sleep_ms(int ms) -> void;

struct MgcMainOptions {
    int network;
    string datadir;
    int p2p_port;
    int rpc_port;
    bool help;
    int addnode_count;
    string addnodes[8];
}

fn _mgc_main_network(string text) -> int {
    if (text == "main" || text == "mainnet") { return 0; }
    if (text == "test" || text == "testnet") { return 1; }
    return 2;
}

fn _mgc_main_print_help() -> void {
    print_str("Magnetar Coin node\n");
    print_str("Usage: mgcd [options]\n");
    print_str("\n");
    print_str("Network and storage:\n");
    print_str("  --network=NAME               main, mainnet, test, testnet or regtest\n");
    print_str("  --datadir=PATH               directory for chain, wallet and cookie files\n");
    print_str("  --help                       print this message and exit\n");
    print_str("\n");
    print_str("Listening sockets:\n");
    print_str("  --port=PORT                  P2P listening port, default 29333\n");
    print_str("  --rpcport=PORT               JSON-RPC listening port, default 29332\n");
    print_str("  --addnode=IP:PORT            seed peer, may be repeated up to 8 times\n");
    print_str("\n");
    print_str("The RPC service listens on loopback only and requires the cookie\n");
    print_str("generated in the data directory with HTTP Basic auth user 'rpc'.\n");
    print_str("When argv[0] contains 'cli' this executable dispatches to mgc_cli_run\n");
    print_str("instead of starting the long-running node event loop. The CLI accepts\n");
    print_str("the same --datadir and --rpcport flags followed by an RPC method name\n");
    print_str("and its positional parameters. It prints the JSON response body.\n");
    print_str("Node shutdown saves the UTXO snapshot, address database and wallet.\n");
    print_str("The RPC stop method sets the node stop flag and returns true.\n");
    print_str("Block generation uses the regtest coinbase address in the wallet.\n");
    print_str("Each accepted block is appended to blocks.log for restart recovery.\n");
    print_str("Peer addresses are persisted in peers.dat between node runs.\n");
    print_str("The cookie file is created with owner-only permissions on startup.\n");
    print_str("RPC requests are accepted one per poll cycle and answered immediately.\n");
    print_str("The event loop sleeps one millisecond when no socket has pending work.\n");
    print_str("Invalid RPC methods return a JSON null result with id preserved.\n");
}

fn _mgc_main_default_datadir(int network) -> string {
    string home = os_get_env("HOME");
    if (home == "" || home == null) { home = "."; }
    string name = "regtest";
    if (network == 0) { name = "mainnet"; }
    if (network == 1) { name = "testnet"; }
    string path = str_concat(home, "/.mgc/");
    path = str_concat(path, name);
    return path;
}

fn _mgc_main_parse_options(int argc, char** argv, MgcMainOptions* o) -> void {
    o.network = 2;
    o.datadir = "";
    o.p2p_port = 29333;
    o.rpc_port = 29332;
    o.help = false;
    o.addnode_count = 0;
    int i = 1;
    while (i < argc) {
        string a = _mgc_cli_arg(argv, i);
        if (a == null || a == "") { i = i + 1; continue; }
        if (a == "--help") {
            o.help = true;
        } else if (str_starts_with(a, "--network=")) {
            o.network = _mgc_main_network(str_substr(a, 10, len(a) - 10));
        } else if (str_starts_with(a, "--datadir=")) {
            o.datadir = str_substr(a, 10, len(a) - 10);
        } else if (str_starts_with(a, "--port=")) {
            o.p2p_port = str_to_int(str_substr(a, 7, len(a) - 7));
        } else if (str_starts_with(a, "--rpcport=")) {
            o.rpc_port = str_to_int(str_substr(a, 10, len(a) - 10));
        } else if (str_starts_with(a, "--addnode=")) {
            if (o.addnode_count < 8) {
                o.addnodes[o.addnode_count] = str_substr(a, 10, len(a) - 10);
                o.addnode_count = o.addnode_count + 1;
            }
        }
        i = i + 1;
    }
    if (o.datadir == "" || o.datadir == null) {
        o.datadir = _mgc_main_default_datadir(o.network);
    }
    if (o.p2p_port < 1 || o.p2p_port > 65535) { o.p2p_port = 29333; }
    if (o.rpc_port < 1 || o.rpc_port > 65535) { o.rpc_port = 29332; }
}

fn _mgc_main_is_cli(int argc, char** argv) -> bool {
    if (argv == null || argc <= 0) { return false; }
    string prog = _mgc_cli_arg(argv, 0);
    int slash = str_last_index_of(prog, "/");
    string prog_base = prog;
    if (slash >= 0) { prog_base = str_substr(prog, slash + 1, len(prog) - slash - 1); }
    if (str_index_of(prog_base, "cli") >= 0) { return true; }
    return false;
}

fn _mgc_main_check_ports(MgcMainOptions* o) -> bool {
    if (o.p2p_port == o.rpc_port) { return false; }
    if (o.p2p_port < 1024 || o.rpc_port < 1024) { return false; }
    if (o.p2p_port > 65535 || o.rpc_port > 65535) { return false; }
    return true;
}

fn _mgc_main_print_startup(MgcMainOptions* o) -> void {
    print_str("Magnetar Coin node starting\n");
    print_str("Network: ");
    if (o.network == 0) { print_str("mainnet\n"); }
    else if (o.network == 1) { print_str("testnet\n"); }
    else { print_str("regtest\n"); }
    print_str("Data directory: ");
    print_str(o.datadir);
    print_str("\n");
    print_str("P2P port: ");
    print(o.p2p_port);
    print_str("\n");
    print_str("RPC port: ");
    print(o.rpc_port);
    print_str("\n");
}

fn _mgc_main_print_shutdown() -> void {
    print_str("MGC node shutdown complete\n");
}

fn main(int argc, char** argv) -> int {
    if (_mgc_main_is_cli(argc, argv)) { return mgc_cli_run(argc, argv); }

    MgcMainOptions opts;
    _mgc_main_parse_options(argc, argv, &opts);
    if (opts.help) {
        _mgc_main_print_help();
        return 0;
    }
    if (!_mgc_main_check_ports(&opts)) {
        print_str("Invalid node port configuration\n");
        return 1;
    }
    _mgc_main_print_startup(&opts);

    MgcNode node;
    MgcRpcServer server;
    if (!mgc_node_init(&node, opts.network, opts.datadir, opts.p2p_port, opts.rpc_port)) {
        print_str("MGC node initialization failed\n");
        return 1;
    }
    mgc_node_load(&node);
    for (int i = 0; i < opts.addnode_count; i = i + 1) {
        mgc_node_addnode(&node, opts.addnodes[i]);
    }
    if (!mgc_node_start_peers(&node)) {
        print_str("MGC P2P start failed\n");
        mgc_node_shutdown(&node);
        return 1;
    }
    if (!mgc_rpc_server_init(&server, opts.rpc_port, cast<string>(node.cookie), 32)) {
        print_str("MGC RPC start failed\n");
        mgc_node_shutdown(&node);
        return 1;
    }

    print_str("Magnetar Coin node ready\n");
    while (true) {
        int rpc_work = mgc_rpc_pump(&server, &node, 5);
        int peer_work = mgc_peer_pump(node.pref, 5);
        if (node.stop) { break; }
        if (rpc_work == 0 && peer_work == 0) { sleep_ms(1); }
    }

    mgc_node_save(&node);
    mgc_rpc_server_free(&server);
    mgc_node_shutdown(&node);
    _mgc_main_print_shutdown();
    return 0;
}
