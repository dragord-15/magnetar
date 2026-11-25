// stubs.mg — Compatibility wrappers for legacy APIs.
// Prefer real modules: lib/crypto.mg, lib/random.mg, lib/net.mg, lib/http.mg, lib/json.mg.
// This file remains compilable for old code that still imports it.

use "lib/crypto.mg";
use "lib/random.mg";
use "lib/net.mg";

// Regex stub (real regex engine not implemented in stdlib yet)
fn regex_match(string pattern, string text) -> bool {
    if (pattern == null || text == null) { return false; }
    return str_index_of(text, pattern) >= 0;
}

class Regex {
    string pattern;
    fn init(string p) -> void { pattern = p; }
    fn isMatch(string text) -> bool { return regex_match(pattern, text); }
}

// SQL stub (real SQL driver not implemented in stdlib yet)
fn sql_connect(string uri) -> int { return 0; }
fn sql_query(int db, string q) -> string { return ""; }

class Database {
    int conn;
    fn connect(string uri) -> bool { conn = sql_connect(uri); return conn != 0; }
    fn execute(string query) -> string { return sql_query(conn, query); }
}

// Legacy graphics names (prefer lib/gui.mg / lib/game2d.mg)
extern fn gfx_init(int width, int height, string title) -> void;
extern fn gfx_clear() -> void;
extern fn gfx_draw_line(int x1, int y1, int x2, int y2) -> void;
extern fn gfx_draw_text(int x, int y, string text) -> void;
extern fn gfx_update() -> void;
extern fn gfx_is_open() -> bool;
