// ============================================================================
// Magnetar Standard Library: Telegram Bot API Client (lib/telegram.mg)
//
// Full-featured Telegram Bot API wrapper using the Magnetar HTTP/TLS stack.
// Pure functions with no mutable global string state.
//
// Supports:
//   - Long-polling update loop (getUpdates)
//   - Sending text messages (normal / Markdown / HTML)
//   - Replying to messages, inline keyboards, callback queries
//   - Sending photos, documents (by URL), location
//   - Editing and deleting messages
//   - Bot & Chat info (getMe, getChat)
//   - Webhook management
//   - Command parsing helpers
// ============================================================================

use "lib/http.mg";
use "lib/string.mg";
use "lib/buffer.mg";
use "lib/time.mg";
use "lib/console.mg";

// ============================================================================
// Data Structures
// ============================================================================

struct TelegramUser {
    int id;
    string first_name;
    string last_name;
    string username;
    bool is_bot;
};

struct TelegramChat {
    int id;
    string chat_type;
    string title;
    string username;
    string first_name;
    string last_name;
};

struct TelegramResult {
    bool ok;
    int message_id;
    string error;
    string raw_body;
};

// Represents a single received update (message or button callback)
struct TelegramUpdateItem {
    int update_id;
    int chat_id;
    int message_id;
    int from_id;
    string text;
    string first_name;
    string username;
    bool is_callback;
    string callback_data;
    string callback_id;
    bool valid;
};

// ============================================================================
// JSON Builder Helpers
// ============================================================================

fn _tg_json_str(string key, string value) -> string {
    StringBuilder sb;
    sb.init(64);
    sb.append("\"");
    sb.append(key);
    sb.append("\":\"");
    sb.append(http_json_escape(value));
    sb.append("\"");
    string result = sb.to_string();
    sb.free_builder();
    return result;
}

fn _tg_json_int(string key, int value) -> string {
    StringBuilder sb;
    sb.init(32);
    sb.append("\"");
    sb.append(key);
    sb.append("\":");
    sb.append(int_to_str(value));
    string result = sb.to_string();
    sb.free_builder();
    return result;
}

fn _tg_json_bool(string key, bool value) -> string {
    StringBuilder sb;
    sb.init(32);
    sb.append("\"");
    sb.append(key);
    sb.append("\":");
    if (value) { sb.append("true"); }
    else       { sb.append("false"); }
    string result = sb.to_string();
    sb.free_builder();
    return result;
}

// ============================================================================
// JSON Object Parser Helpers
// ============================================================================

fn _tg_find_obj_start(string json, int pos) -> int {
    int n = len(json);
    char* p = cast<char*>(json);
    for (int i = pos; i < n; i = i + 1) {
        if (*(p + i) == 123) { return i; }
    }
    return -1;
}

fn _tg_find_obj_end(string json, int pos) -> int {
    int n = len(json);
    char* p = cast<char*>(json);
    int depth = 0;
    bool in_str = false;
    for (int i = pos; i < n; i = i + 1) {
        int c = cast<int>(*(p + i)) & 255;
        if (in_str) {
            if (c == 92 && i + 1 < n) { i = i + 1; continue; }
            if (c == 34) { in_str = false; }
            continue;
        }
        if (c == 34)  { in_str = true; continue; }
        if (c == 123) { depth = depth + 1; }
        if (c == 125) {
            depth = depth - 1;
            if (depth == 0) { return i; }
        }
    }
    return -1;
}

fn _tg_parse_user(string json) -> TelegramUser {
    TelegramUser u;
    u.id = http_json_get_int(json, "id");
    u.first_name = http_json_get_string(json, "first_name");
    u.last_name = http_json_get_string(json, "last_name");
    u.username = http_json_get_string(json, "username");
    u.is_bot = (str_index_of(json, "\"is_bot\":true") >= 0);
    return u;
}

fn _tg_parse_chat(string json) -> TelegramChat {
    TelegramChat c;
    c.id = http_json_get_int(json, "id");
    c.chat_type = http_json_get_string(json, "type");
    c.title = http_json_get_string(json, "title");
    c.username = http_json_get_string(json, "username");
    c.first_name = http_json_get_string(json, "first_name");
    c.last_name = http_json_get_string(json, "last_name");
    return c;
}

// Parse a single update JSON snippet into TelegramUpdateItem
fn tg_parse_update_item(string update_json) -> TelegramUpdateItem {
    TelegramUpdateItem item;
    item.valid = false;
    item.update_id = 0;
    item.chat_id = 0;
    item.message_id = 0;
    item.from_id = 0;
    item.text = "";
    item.first_name = "";
    item.username = "";
    item.is_callback = false;
    item.callback_data = "";
    item.callback_id = "";

    if (update_json == null || len(update_json) < 5) { return item; }

    item.update_id = http_json_get_int(update_json, "update_id");
    if (item.update_id <= 0) { return item; }

    // Check for callback_query
    int cb_pos = str_index_of(update_json, "\"callback_query\"");
    if (cb_pos >= 0) {
        int cbs = _tg_find_obj_start(update_json, cb_pos);
        if (cbs >= 0) {
            int cbe = _tg_find_obj_end(update_json, cbs);
            if (cbe > cbs) {
                string cbj = str_substr(update_json, cbs, cbe - cbs + 1);
                item.is_callback = true;
                item.callback_data = http_json_get_string(cbj, "data");
                item.callback_id = http_json_get_string(cbj, "id");
                item.text = item.callback_data;

                // User in callback
                int cbf = str_index_of(cbj, "\"from\"");
                if (cbf >= 0) {
                    int cbfs = _tg_find_obj_start(cbj, cbf);
                    if (cbfs >= 0) {
                        int cbfe = _tg_find_obj_end(cbj, cbfs);
                        if (cbfe > cbfs) {
                            string cbfj = str_substr(cbj, cbfs, cbfe - cbfs + 1);
                            item.from_id = http_json_get_int(cbfj, "id");
                            item.first_name = http_json_get_string(cbfj, "first_name");
                            item.username = http_json_get_string(cbfj, "username");
                        }
                    }
                }

                // Chat from message inside callback
                int cbm = str_index_of(cbj, "\"message\"");
                if (cbm >= 0) {
                    int cbms = _tg_find_obj_start(cbj, cbm);
                    if (cbms >= 0) {
                        int cbme = _tg_find_obj_end(cbj, cbms);
                        if (cbme > cbms) {
                            string cbmj = str_substr(cbj, cbms, cbme - cbms + 1);
                            item.message_id = http_json_get_int(cbmj, "message_id");
                            int c_pos = str_index_of(cbmj, "\"chat\"");
                            if (c_pos >= 0) {
                                int cs = _tg_find_obj_start(cbmj, c_pos);
                                if (cs >= 0) {
                                    int ce = _tg_find_obj_end(cbmj, cs);
                                    if (ce > cs) {
                                        item.chat_id = http_json_get_int(str_substr(cbmj, cs, ce - cs + 1), "id");
                                    }
                                }
                            }
                        }
                    }
                }

                item.valid = true;
                return item;
            }
        }
    }

    // Standard message
    item.message_id = http_json_get_int(update_json, "message_id");
    item.text = http_json_get_string(update_json, "text");

    // Chat object
    int chat_pos = str_index_of(update_json, "\"chat\"");
    if (chat_pos >= 0) {
        int cs = _tg_find_obj_start(update_json, chat_pos);
        if (cs >= 0) {
            int ce = _tg_find_obj_end(update_json, cs);
            if (ce > cs) {
                string chat_json = str_substr(update_json, cs, ce - cs + 1);
                item.chat_id = http_json_get_int(chat_json, "id");
            }
        }
    }

    // From user object
    int from_pos = str_index_of(update_json, "\"from\"");
    if (from_pos >= 0) {
        int fs = _tg_find_obj_start(update_json, from_pos);
        if (fs >= 0) {
            int fe = _tg_find_obj_end(update_json, fs);
            if (fe > fs) {
                string from_json = str_substr(update_json, fs, fe - fs + 1);
                item.from_id = http_json_get_int(from_json, "id");
                item.first_name = http_json_get_string(from_json, "first_name");
                item.username = http_json_get_string(from_json, "username");
            }
        }
    }

    item.valid = (item.chat_id != 0);
    return item;
}

// ============================================================================
// Command Parsing Helpers
// ============================================================================

fn tg_is_command(string text) -> bool {
    if (text == null || len(text) < 2) { return false; }
    char* p = cast<char*>(text);
    return *(p + 0) == 47;
}

fn tg_command_name(string text) -> string {
    if (!tg_is_command(text)) { return ""; }
    int n = len(text);
    char* p = cast<char*>(text);
    int end_pos = 1;
    while (end_pos < n) {
        int c = cast<int>(*(p + end_pos)) & 255;
        if (c == 32 || c == 64) { break; }
        end_pos = end_pos + 1;
    }
    return str_substr(text, 1, end_pos - 1);
}

fn tg_command_args(string text) -> string {
    if (!tg_is_command(text)) { return ""; }
    int n = len(text);
    char* p = cast<char*>(text);
    int i = 1;
    while (i < n && *(p + i) != 32) { i = i + 1; }
    while (i < n && *(p + i) == 32) { i = i + 1; }
    if (i >= n) { return ""; }
    return str_substr(text, i, n - i);
}

// ============================================================================
// Core API Call
// ============================================================================

fn tg_api_call(string token, string method, string json_body, int timeout_ms) -> TelegramResult {
    TelegramResult res;
    res.ok = false;
    res.message_id = 0;
    res.error = "";
    res.raw_body = "";

    if (timeout_ms <= 0) { timeout_ms = 35000; }
    string url = str_concat("https://api.telegram.org/bot", str_concat(token, str_concat("/", method)));

    HttpResponse resp;
    if (len(json_body) > 0) {
        resp = http_request_ex("POST", url, json_body, "application/json", "", true, timeout_ms, true);
    } else {
        resp = http_request_ex("GET", url, "", "", "", true, timeout_ms, true);
    }

    if (resp.error != "") {
        res.error = resp.error;
        return res;
    }

    res.raw_body = resp.body;
    if (str_index_of(resp.body, "\"ok\":true") >= 0) {
        res.ok = true;
    }

    if (!res.ok) {
        res.error = http_json_get_string(resp.body, "description");
        if (len(res.error) == 0) {
            res.error = str_concat("API error (HTTP ", str_concat(int_to_str(resp.status_code), ")"));
        }
    }

    res.message_id = http_json_get_int(resp.body, "message_id");
    return res;
}

// ============================================================================
// Public API Functions
// ============================================================================

// Get info about the bot
fn tg_get_me(string token) -> TelegramUser {
    TelegramResult res = tg_api_call(token, "getMe", "", 15000);
    TelegramUser user;
    user.id = 0;
    user.first_name = "";
    user.last_name = "";
    user.username = "";
    user.is_bot = false;
    if (res.ok) {
        int rp = str_index_of(res.raw_body, "\"result\"");
        if (rp >= 0) {
            int os = _tg_find_obj_start(res.raw_body, rp);
            if (os >= 0) {
                int oe = _tg_find_obj_end(res.raw_body, os);
                if (oe > os) {
                    string rj = str_substr(res.raw_body, os, oe - os + 1);
                    user = _tg_parse_user(rj);
                }
            }
        }
    }
    return user;
}

// Send standard message
fn tg_send_message(string token, int chat_id, string text) -> TelegramResult {
    StringBuilder sb;
    sb.init(256);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_str("text", text));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendMessage", body, 15000);
}

// Send Markdown message
fn tg_send_message_md(string token, int chat_id, string text) -> TelegramResult {
    StringBuilder sb;
    sb.init(256);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_str("text", text));
    sb.append(",");
    sb.append(_tg_json_str("parse_mode", "Markdown"));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendMessage", body, 15000);
}

// Send HTML message
fn tg_send_message_html(string token, int chat_id, string text) -> TelegramResult {
    StringBuilder sb;
    sb.init(256);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_str("text", text));
    sb.append(",");
    sb.append(_tg_json_str("parse_mode", "HTML"));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendMessage", body, 15000);
}

// Reply to specific message
fn tg_reply(string token, int chat_id, int reply_to_id, string text) -> TelegramResult {
    StringBuilder sb;
    sb.init(256);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_str("text", text));
    sb.append(",");
    sb.append(_tg_json_int("reply_to_message_id", reply_to_id));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendMessage", body, 15000);
}

// Send message with inline keyboard
fn tg_send_message_keyboard(string token, int chat_id, string text, string reply_markup_json) -> TelegramResult {
    StringBuilder sb;
    sb.init(512);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_str("text", text));
    sb.append(",\"reply_markup\":");
    sb.append(reply_markup_json);
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendMessage", body, 15000);
}

// Send Markdown message with inline keyboard
fn tg_send_message_md_keyboard(string token, int chat_id, string text, string reply_markup_json) -> TelegramResult {
    StringBuilder sb;
    sb.init(512);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_str("text", text));
    sb.append(",");
    sb.append(_tg_json_str("parse_mode", "Markdown"));
    sb.append(",\"reply_markup\":");
    sb.append(reply_markup_json);
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendMessage", body, 15000);
}

// Edit existing message text
fn tg_edit_message(string token, int chat_id, int message_id, string text) -> TelegramResult {
    StringBuilder sb;
    sb.init(256);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_int("message_id", message_id));
    sb.append(",");
    sb.append(_tg_json_str("text", text));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "editMessageText", body, 15000);
}

// Delete message
fn tg_delete_message(string token, int chat_id, int message_id) -> TelegramResult {
    StringBuilder sb;
    sb.init(128);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_int("message_id", message_id));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "deleteMessage", body, 15000);
}

// Answer callback query
fn tg_answer_callback(string token, string callback_query_id, string text, bool show_alert) -> TelegramResult {
    StringBuilder sb;
    sb.init(256);
    sb.append("{");
    sb.append(_tg_json_str("callback_query_id", callback_query_id));
    if (len(text) > 0) {
        sb.append(",");
        sb.append(_tg_json_str("text", text));
    }
    if (show_alert) {
        sb.append(",");
        sb.append(_tg_json_bool("show_alert", true));
    }
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "answerCallbackQuery", body, 15000);
}

// Send photo by URL
fn tg_send_photo(string token, int chat_id, string photo_url, string caption) -> TelegramResult {
    StringBuilder sb;
    sb.init(256);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_str("photo", photo_url));
    if (len(caption) > 0) {
        sb.append(",");
        sb.append(_tg_json_str("caption", caption));
    }
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendPhoto", body, 20000);
}

// Send document by URL
fn tg_send_document(string token, int chat_id, string document_url, string caption) -> TelegramResult {
    StringBuilder sb;
    sb.init(256);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_str("document", document_url));
    if (len(caption) > 0) {
        sb.append(",");
        sb.append(_tg_json_str("caption", caption));
    }
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendDocument", body, 20000);
}

// Send location
fn tg_send_location(string token, int chat_id, string latitude, string longitude) -> TelegramResult {
    StringBuilder sb;
    sb.init(128);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",\"latitude\":");
    sb.append(latitude);
    sb.append(",\"longitude\":");
    sb.append(longitude);
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendLocation", body, 15000);
}

// Chat action (typing indicator)
fn tg_send_chat_action(string token, int chat_id, string action) -> TelegramResult {
    StringBuilder sb;
    sb.init(128);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append(",");
    sb.append(_tg_json_str("action", action));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "sendChatAction", body, 15000);
}

fn tg_send_typing(string token, int chat_id) -> TelegramResult {
    return tg_send_chat_action(token, chat_id, "typing");
}

// Get chat info
fn tg_get_chat(string token, int chat_id) -> TelegramChat {
    StringBuilder sb;
    sb.init(64);
    sb.append("{");
    sb.append(_tg_json_int("chat_id", chat_id));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    TelegramResult res = tg_api_call(token, "getChat", body, 15000);
    TelegramChat chat;
    chat.id = 0;
    chat.chat_type = "";
    chat.title = "";
    chat.username = "";
    chat.first_name = "";
    chat.last_name = "";
    if (res.ok) {
        int rp = str_index_of(res.raw_body, "\"result\"");
        if (rp >= 0) {
            int os = _tg_find_obj_start(res.raw_body, rp);
            if (os >= 0) {
                int oe = _tg_find_obj_end(res.raw_body, os);
                if (oe > os) {
                    string rj = str_substr(res.raw_body, os, oe - os + 1);
                    chat = _tg_parse_chat(rj);
                }
            }
        }
    }
    return chat;
}

// Webhook management
fn tg_set_webhook(string token, string webhook_url) -> TelegramResult {
    StringBuilder sb;
    sb.init(128);
    sb.append("{");
    sb.append(_tg_json_str("url", webhook_url));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();
    return tg_api_call(token, "setWebhook", body, 15000);
}

fn tg_delete_webhook(string token) -> TelegramResult {
    return tg_api_call(token, "deleteWebhook", "", 15000);
}

// ============================================================================
// Inline Keyboard Builders
// ============================================================================

fn tg_inline_button(string text, string callback_data) -> string {
    StringBuilder sb;
    sb.init(128);
    sb.append("{");
    sb.append(_tg_json_str("text", text));
    sb.append(",");
    sb.append(_tg_json_str("callback_data", callback_data));
    sb.append("}");
    string result = sb.to_string();
    sb.free_builder();
    return result;
}

fn tg_url_button(string text, string url) -> string {
    StringBuilder sb;
    sb.init(128);
    sb.append("{");
    sb.append(_tg_json_str("text", text));
    sb.append(",");
    sb.append(_tg_json_str("url", url));
    sb.append("}");
    string result = sb.to_string();
    sb.free_builder();
    return result;
}

fn tg_keyboard_1(string btn1) -> string {
    return str_concat("{\"inline_keyboard\":[[", str_concat(btn1, "]]}"));
}

fn tg_keyboard_2(string btn1, string btn2) -> string {
    StringBuilder sb;
    sb.init(256);
    sb.append("{\"inline_keyboard\":[[");
    sb.append(btn1);
    sb.append(",");
    sb.append(btn2);
    sb.append("]]}");
    string result = sb.to_string();
    sb.free_builder();
    return result;
}

fn tg_keyboard_rows_2(string btn1, string btn2) -> string {
    StringBuilder sb;
    sb.init(256);
    sb.append("{\"inline_keyboard\":[[");
    sb.append(btn1);
    sb.append("],[");
    sb.append(btn2);
    sb.append("]]}");
    string result = sb.to_string();
    sb.free_builder();
    return result;
}

fn tg_keyboard_3(string btn1, string btn2, string btn3) -> string {
    StringBuilder sb;
    sb.init(384);
    sb.append("{\"inline_keyboard\":[[");
    sb.append(btn1);
    sb.append(",");
    sb.append(btn2);
    sb.append(",");
    sb.append(btn3);
    sb.append("]]}");
    string result = sb.to_string();
    sb.free_builder();
    return result;
}

// Fetch raw updates JSON from Telegram
fn tg_fetch_updates_json(string token, int offset, int timeout_sec) -> string {
    if (timeout_sec <= 0) { timeout_sec = 25; }
    int req_timeout = (timeout_sec + 5) * 1000;

    StringBuilder sb;
    sb.init(128);
    sb.append("{");
    sb.append(_tg_json_int("offset", offset));
    sb.append(",");
    sb.append(_tg_json_int("limit", 20));
    sb.append(",");
    sb.append(_tg_json_int("timeout", timeout_sec));
    sb.append(",\"allowed_updates\":[\"message\",\"callback_query\"]}");
    string body = sb.to_string();
    sb.free_builder();

    TelegramResult res = tg_api_call(token, "getUpdates", body, req_timeout);
    if (!res.ok) { return ""; }
    return res.raw_body;
}
