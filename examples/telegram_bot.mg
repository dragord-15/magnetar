// ============================================================================
// Magnetar Telegram Bot + Real Generative AI (LLM)
//
// A full-featured Telegram bot powered by REAL Generative AI & Large Language Models
// written entirely in Magnetar.
//
// Uses:
//   - lib/telegram.mg: Telegram Bot API over HTTPS
//   - lib/llm.mg: Direct connection to Google Gemini / Groq / Ollama
//   - lib/bot_ai.mg: Fallback & Natural Language Processing
//
// Supported AI Providers:
//   1. Google Gemini (gemini-1.5-flash / gemini-2.0-flash) - Free & fast
//   2. Groq (Llama 3.3 70B) - Ultra-fast
//   3. Ollama - 100% Local on machine (no API key needed)
//
// To run:
//   ./magc examples/telegram_bot.mg -o telegram_bot
//   ./telegram_bot
// ============================================================================

use "lib/telegram.mg";
use "lib/llm.mg";
use "lib/bot_ai.mg";
use "lib/time.mg";
use "lib/console.mg";
use "lib/string.mg";

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  1. TELEGRAM BOT TOKEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
fn get_bot_token() -> string {
    return "YOUR_BOT_TOKEN_HERE";
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  2. REAL GENERATIVE AI (LLM) CONFIGURATION
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Put your free API key here:
// • Google Gemini (مجاني 100% بدون بطاقة بنكية): https://aistudio.google.com/app/apikey (يبدأ بـ AIzaSy)
// • Groq (مجاني 100% بدون بطاقة بنكية): https://console.groq.com/keys (يبدأ بـ gsk_)
// • أو اتركه فارغاً وسيعمل الذكاء الاصطناعي التوليدي المجاني تلقائياً!
fn get_ai_api_key() -> string {
    return "";
}

fn get_ai_provider() -> string {
    string key = get_ai_api_key();
    if (str_starts_with(key, "AIzaSy")) { return "Google Gemini"; }
    if (str_starts_with(key, "gsk_")) { return "Groq (GPT-OSS 120B)"; }
    return "Auto (Free Real AI & NLP)";
}

// AI System Prompt (Defines the bot's persona and instructions)
fn get_ai_system_prompt() -> string {
    return "أنت Dragord، مساعد ذكاء اصطناعي متقدم وودود تم برمجته وتطويره بواسطة المبرمج أسامة (Oussama) باستخدام لغة البرمجة المبتكرة Magnetar التي تترجم مباشرة إلى لغة التجميع x86-64 Assembly. أجب دائماً بذكاء ودقة وتنسيق جميل واحترافي باللغة العربية (أو بلغة المستخدم). ساعد المستخدم في أي موضوع: برمجة، أمن سيبراني، حسابات، معلومات عامة ونقاشات مفيدة.";
}

// ============================================================================
// Core Generative AI Dispatcher
// ============================================================================

fn generate_real_ai_reply(string user_prompt, string user_name) -> string {
    string api_key = get_ai_api_key();
    string sys_prompt = get_ai_system_prompt();

    // 1. If key starts with AIzaSy -> Google Gemini
    if (str_starts_with(api_key, "AIzaSy")) {
        return llm_gemini_generate(api_key, "gemini-1.5-flash", sys_prompt, user_prompt, 800);
    }

    // 2. If key starts with gsk_ -> Groq (GPT-OSS 120B)
    if (str_starts_with(api_key, "gsk_")) {
        return llm_groq_generate(api_key, "openai/gpt-oss-120b", sys_prompt, user_prompt, 800);
    }

    // 3. Try Free Real Generative AI (No key needed)
    string free_ans = llm_pollinations_generate(sys_prompt, user_prompt);
    if (len(free_ans) > 0) {
        return free_ans;
    }

    // 4. Intelligent Conversational Engine Fallback
    return ai_chat_reply(user_prompt, user_name);
}

// ============================================================================
// Command Handlers
// ============================================================================

fn handle_start(string token, int chat_id, string first_name) -> void {
    StringBuilder sb;
    sb.init(512);
    sb.append("👋 *مرحباً ");
    if (len(first_name) > 0) {
        sb.append(first_name);
    } else {
        sb.append("بك");
    }
    sb.append("!*\n\n");
    sb.append("أنا بوت **ذكاء اصطناعي حقيقي (Generative AI / LLM)** مبني بلغة *Magnetar* 🚀🤖\n\n");
    sb.append("💬 **لست مبرمجاً بإجابات محفوظة مسبقاً!**\n");
    sb.append("يمكنك كتابة أي سؤال أو فكرة أو موضوع، وسأفكر وأجيبك بذكاء في أي مجال.\n\n");
    sb.append("جرب أن تسألني الآن أو تضغط على الأزرار أدناه:");
    string text = sb.to_string();
    sb.free_builder();

    string btn1 = tg_inline_button("📋 الأوامر", "cmd_help");
    string btn2 = tg_inline_button("ℹ️ حول البوت", "cmd_about");
    string btn3 = tg_inline_button("⏰ الوقت", "cmd_time");
    string keyboard = tg_keyboard_3(btn1, btn2, btn3);

    tg_send_message_md_keyboard(token, chat_id, text, keyboard);
}

fn handle_help(string token, int chat_id) -> void {
    StringBuilder sb;
    sb.init(600);
    sb.append("📋 *إمكانيات وأوامر الذكاء الاصطناعي:*\n\n");
    sb.append("🧠 *الدردشة الحرة (Generative AI):*\n");
    sb.append("اكتب أي رسالة أو سؤال مباشرة بدون أوامر وسأقوم بتحليله وتوليد إجابة حقيقية في أي موضوع (برمجة، فلسفة، علوم، أمن سيبراني، كتابة محتوى، لغات...).\n\n");
    sb.append("⚙️ *الأوامر السريعة:*\n");
    sb.append("/ai <سؤال> - طرح سؤال مباشر\n");
    sb.append("/calc <عملية> - حاسبة رياضية دقيقة\n");
    sb.append("/time - الوقت والتاريخ الحالي للسيرفر\n");
    sb.append("/info - معلومات حسابك\n");
    sb.append("/ping - فحص سرعة استجابة السيرفر\n");
    sb.append("/status - فحص حالة محرك الذكاء الاصطناعي\n");
    sb.append("/about - معلومات عن لغة Magnetar ومطور البوت\n");
    string text = sb.to_string();
    sb.free_builder();

    tg_send_message_md(token, chat_id, text);
}

fn handle_ai_command(string token, int chat_id, string args, string first_name) -> void {
    if (len(args) == 0) {
        tg_send_message(token, chat_id, "اكتب سؤالك بعد الأمر.\nمثال: /ai كيف يعمل الذكاء الاصطناعي التوليدي؟");
        return;
    }
    tg_send_typing(token, chat_id);
    string reply = generate_real_ai_reply(args, first_name);
    tg_send_message_md(token, chat_id, reply);
}

fn handle_echo(string token, int chat_id, int reply_to_id, string args) -> void {
    if (len(args) == 0) {
        tg_send_message(token, chat_id, "أرسل نصاً بعد الأمر.\nمثال: /echo مرحباً");
        return;
    }
    string echo_reply = str_concat("🔁 ", args);
    tg_reply(token, chat_id, reply_to_id, echo_reply);
}

fn handle_info(string token, int chat_id, string username, string first_name, int from_id) -> void {
    StringBuilder sb;
    sb.init(512);
    sb.append("📊 *معلومات المستخدم:*\n\n");
    sb.append("🆔 المعرّف: `");
    sb.append(int_to_str(from_id));
    sb.append("`\n");
    sb.append("👤 الاسم: ");
    sb.append(first_name);
    sb.append("\n");
    if (len(username) > 0) {
        sb.append("📱 اسم المستخدم: @");
        sb.append(username);
        sb.append("\n");
    }
    sb.append("💬 معرّف المحادثة: `");
    sb.append(int_to_str(chat_id));
    sb.append("`\n");
    string text = sb.to_string();
    sb.free_builder();

    tg_send_message_md(token, chat_id, text);
}

fn handle_time(string token, int chat_id) -> void {
    DateTime dt;
    dt.now();
    StringBuilder sb;
    sb.init(256);
    sb.append("⏰ *الوقت الحالي للسيرفر:*\n\n");
    sb.append("📅 التاريخ: ");
    sb.append(dt.format_date());
    sb.append("\n");
    sb.append("🕐 الساعة: ");
    sb.append(dt.format_time());
    sb.append(" UTC\n");
    sb.append("📆 اليوم: ");
    sb.append(dt.weekday_name());
    sb.append("\n");
    string text = sb.to_string();
    sb.free_builder();

    tg_send_message_md(token, chat_id, text);
}

fn handle_ping(string token, int chat_id) -> void {
    int start = time_now();
    TelegramResult res = tg_send_message(token, chat_id, "🏓 Pong!");
    int elapsed = time_now() - start;
    if (res.ok && elapsed >= 0) {
        StringBuilder sb;
        sb.init(128);
        sb.append("⚡ سرعة الاستجابة: ~");
        sb.append(int_to_str(elapsed));
        sb.append(" ثانية");
        string text = sb.to_string();
        sb.free_builder();
        tg_send_message(token, chat_id, text);
    }
}

fn handle_about(string token, int chat_id) -> void {
    StringBuilder sb;
    sb.init(512);
    sb.append("🤖 *Magnetar Telegram Bot + Real LLM*\n\n");
    sb.append("بوت محادثة وذكاء اصطناعي توليدي حقيقي مبني بلغة *Magnetar*،\n");
    sb.append("مُجمَّع مباشرة إلى x86-64 Machine Code.\n\n");
    sb.append("⚙️ *المميزات التقنية:*\n");
    sb.append("• مدعوم بنماذج الذكاء الاصطناعي الكبيرة (LLMs)\n");
    sb.append("• إجابات ذكية مولدة آنياً بدون نصوص محفوظة\n");
    sb.append("• اتصال آمن ومباشر عبر بروتوكول HTTPS/TLS\n");
    sb.append("• استطلاع التحديثات عبر Long Polling\n\n");
    sb.append("📦 *المكتبات المستخدمة:*\n");
    sb.append("• lib/llm.mg (محرك نماذج LLM)\n");
    sb.append("• lib/telegram.mg & lib/http.mg\n");
    sb.append("• lib/string.mg & lib/time.mg\n");
    string text = sb.to_string();
    sb.free_builder();

    string btn = tg_url_button("🌐 مستودع المشروع", "https://github.com");
    string keyboard = tg_keyboard_1(btn);
    tg_send_message_md_keyboard(token, chat_id, text, keyboard);
}

fn handle_calc(string token, int chat_id, string expr) -> void {
    if (len(expr) == 0) {
        tg_send_message(token, chat_id, "أرسل عملية حسابية.\nمثال: /calc 5+3");
        return;
    }

    int n = len(expr);
    char* p = cast<char*>(expr);
    int op_pos = -1;
    char op_char = '+';

    for (int i = 1; i < n; i = i + 1) {
        int c = cast<int>(*(p + i)) & 255;
        if (c == 43 || c == 45 || c == 42 || c == 47) {
            op_pos = i;
            op_char = *(p + i);
            break;
        }
    }

    if (op_pos < 0) {
        tg_send_message(token, chat_id, "لم يتم العثور على معامل (+, -, *, /).\nمثال: /calc 12*8");
        return;
    }

    string left_str = str_trim(str_substr(expr, 0, op_pos));
    string right_str = str_trim(str_substr(expr, op_pos + 1, n - op_pos - 1));
    int left = str_to_int(left_str);
    int right = str_to_int(right_str);
    int result = 0;
    string op_name = "";

    if (op_char == '+') { result = left + right; op_name = "+"; }
    if (op_char == '-') { result = left - right; op_name = "-"; }
    if (op_char == '*') { result = left * right; op_name = "×"; }
    if (op_char == '/') {
        if (right == 0) {
            tg_send_message(token, chat_id, "❌ لا يمكن القسمة على صفر!");
            return;
        }
        result = left / right;
        op_name = "÷";
    }

    StringBuilder sb;
    sb.init(256);
    sb.append("🔢 *حاسبة Magnetar:*\n\n");
    sb.append(int_to_str(left));
    sb.append(" ");
    sb.append(op_name);
    sb.append(" ");
    sb.append(int_to_str(right));
    sb.append(" = *");
    sb.append(int_to_str(result));
    sb.append("*");
    string text = sb.to_string();
    sb.free_builder();

    tg_send_message_md(token, chat_id, text);
}

fn handle_status(string token, int chat_id) -> void {
    DateTime dt;
    dt.now();
    StringBuilder sb;
    sb.init(512);
    sb.append("📊 *حالة البوت:*\n\n");
    sb.append("✅ الحالة: متصل ونشط\n");
    sb.append("🧠 محرك الذكاء الاصطناعي: Real LLM (");
    sb.append(get_ai_provider());
    sb.append(")\n");
    sb.append("🖥️ المنصة: Linux x86-64 (Native ELF)\n");
    sb.append("⚡ المترجم: Magnetar magc\n");
    sb.append("🔒 التشفير: TLS / OpenSSL Pipe Bridge\n");
    sb.append("📡 وضع التحديثات: Long Polling\n");
    sb.append("🕐 فحص الوقت: ");
    sb.append(dt.format());
    sb.append(" UTC\n");
    string text = sb.to_string();
    sb.free_builder();

    tg_send_message_md(token, chat_id, text);
}

// ============================================================================
// Callback Handler (inline keyboard buttons)
// ============================================================================

fn handle_callback(string token, int chat_id, string callback_data, string callback_id) -> void {
    tg_answer_callback(token, callback_id, "", false);

    if (callback_data == "cmd_help") {
        handle_help(token, chat_id);
    } else if (callback_data == "cmd_about") {
        handle_about(token, chat_id);
    } else if (callback_data == "cmd_time") {
        handle_time(token, chat_id);
    } else {
        StringBuilder sb;
        sb.init(128);
        sb.append("🔘 تم الضغط على: ");
        sb.append(callback_data);
        string text = sb.to_string();
        sb.free_builder();
        tg_send_message(token, chat_id, text);
    }
}

// ============================================================================
// Process a single update
// ============================================================================

fn process_update(string token, TelegramUpdateItem item) -> void {
    int chat_id    = item.chat_id;
    int msg_id     = item.message_id;
    string text    = item.text;
    string uname   = item.username;
    string fname   = item.first_name;
    int from_id    = item.from_id;

    // Handle Callback Queries (Inline Keyboard Buttons)
    if (item.is_callback) {
        print_cyan("[CALLBACK] ");
        if (len(fname) > 0) {
            print_str(fname);
        } else {
            print_str(int_to_str(from_id));
        }
        print_str(": ");
        print_line(item.callback_data);

        handle_callback(token, chat_id, item.callback_data, item.callback_id);
        return;
    }

    // Log incoming message
    print_green("[MSG] ");
    if (len(fname) > 0) {
        print_str(fname);
    } else {
        print_str(int_to_str(from_id));
    }
    print_str(": ");
    print_line(text);

    // Commands starting with '/'
    if (tg_is_command(text)) {
        string cmd = tg_command_name(text);
        string args = tg_command_args(text);

        if (cmd == "start") {
            handle_start(token, chat_id, fname);
        } else if (cmd == "help") {
            handle_help(token, chat_id);
        } else if (cmd == "ai") {
            handle_ai_command(token, chat_id, args, fname);
        } else if (cmd == "echo") {
            handle_echo(token, chat_id, msg_id, args);
        } else if (cmd == "info") {
            handle_info(token, chat_id, uname, fname, from_id);
        } else if (cmd == "time") {
            handle_time(token, chat_id);
        } else if (cmd == "ping") {
            handle_ping(token, chat_id);
        } else if (cmd == "about") {
            handle_about(token, chat_id);
        } else if (cmd == "calc") {
            handle_calc(token, chat_id, args);
        } else if (cmd == "status") {
            handle_status(token, chat_id);
        } else {
            // If unknown command, pass it to Real Generative AI
            tg_send_typing(token, chat_id);
            string ai_reply = generate_real_ai_reply(text, fname);
            tg_send_message_md(token, chat_id, ai_reply);
        }
    } else {
        // Natural language message: Send typing indicator and generate Real AI answer
        if (len(text) > 0) {
            tg_send_typing(token, chat_id);
            string ai_reply = generate_real_ai_reply(text, fname);
            tg_send_message_md(token, chat_id, ai_reply);
        }
    }
}

// ============================================================================
// Main Entry Point
// ============================================================================

fn main() -> int {
    print_str("\n");
    print_bold("==================================================\n");
    print_bold("  🤖 Magnetar Telegram Bot + Real Generative AI   \n");
    print_bold("  Powered by Magnetar Language (x86-64 native)    \n");
    print_bold("==================================================\n\n");

    string token = get_bot_token();
    if (token == "YOUR_BOT_TOKEN_HERE" || len(token) < 10) {
        print_error("يرجى تعيين توكن البوت في دالة get_bot_token()!");
        print_info("احصل على التوكن من @BotFather على Telegram");
        return 1;
    }

    print_info("جاري الاتصال بـ Telegram API والتحقق من التوكن...");

    // Test connection with getMe
    TelegramUser me = tg_get_me(token);
    if (me.id == 0) {
        print_error("فشل الاتصال بـ Telegram API! يرجى التأكد من التوكن أو اتصال الإنترنت.");
        return 1;
    }

    print_success(str_concat("تم الاتصال بنجاح! البوت: @", me.username));
    print_info(str_concat("اسم البوت: ", me.first_name));
    print_info(str_concat("معرّف البوت: ", int_to_str(me.id)));
    print_info(str_concat("محرك الذكاء الاصطناعي التوليدي: ", get_ai_provider()));
    print_str("\n");
    print_info("🚀 البوت يعمل الآن ويستمع للرسائل... (اضغط Ctrl+C للإيقاف)");
    print_str("\n");

    int last_update_id = 0;

    while (true) {
        string raw_body = tg_fetch_updates_json(token, last_update_id + 1, 25);
        if (len(raw_body) > 0) {
            int result_pos = str_index_of(raw_body, "\"result\"");
            if (result_pos >= 0) {
                int n = len(raw_body);
                char* p = cast<char*>(raw_body);
                int arr_start = result_pos + 8;
                while (arr_start < n && *(p + arr_start) != 91) { arr_start = arr_start + 1; }

                if (arr_start < n) {
                    int cursor = arr_start + 1;
                    while (cursor < n) {
                        int obj_start = _tg_find_obj_start(raw_body, cursor);
                        if (obj_start < 0) { break; }
                        int obj_end = _tg_find_obj_end(raw_body, obj_start);
                        if (obj_end < 0) { break; }

                        string update_json = str_substr(raw_body, obj_start, obj_end - obj_start + 1);
                        TelegramUpdateItem item = tg_parse_update_item(update_json);

                        if (item.valid) {
                            if (item.update_id > last_update_id) {
                                last_update_id = item.update_id;
                            }
                            process_update(token, item);
                        }

                        cursor = obj_end + 1;
                    }
                }
            }
        }
    }

    return 0;
}
