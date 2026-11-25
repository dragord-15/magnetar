// ============================================================================
// Magnetar Standard Library: Node/Service Helpers (lib/node.mg)
// Generic event-loop node skeleton for long-running services.
// For coin node implementation, use coin/lib/node.mg.
// ============================================================================

use "lib/string.mg";

extern fn sleep_ms(int ms) -> void;
extern fn get_timestamp() -> int;

struct NodeConfig {
    string name;
    int tick_ms;
    int max_ticks;   // -1 = run forever
    bool running;
}

fn node_config_default(string name) -> NodeConfig {
    NodeConfig c;
    c.name = name;
    c.tick_ms = 100;
    c.max_ticks = -1;
    c.running = false;
    return c;
}

fn node_log(string node_name, string msg) -> void {
    print_str("[");
    print_str(node_name);
    print_str("] ");
    print_str(msg);
    print_str("\n");
}

fn node_now() -> int {
    return get_timestamp();
}

// Caller drives the loop: while(node_should_run(&c, tick)){ ... c.ticks++; }
struct NodeLoop {
    NodeConfig cfg;
    int ticks;
    int started_at;

    fn init(NodeConfig c) -> void {
        cfg = c;
        ticks = 0;
        started_at = get_timestamp();
        cfg.running = true;
    }

    fn should_run() -> bool {
        if (!cfg.running) { return false; }
        if (cfg.max_ticks >= 0 && ticks >= cfg.max_ticks) { return false; }
        return true;
    }

    fn tick_done() -> void {
        ticks = ticks + 1;
        if (cfg.tick_ms > 0) { sleep_ms(cfg.tick_ms); }
    }

    fn stop() -> void {
        cfg.running = false;
    }

    fn uptime_sec() -> int {
        int now = get_timestamp();
        return now - started_at;
    }
}
