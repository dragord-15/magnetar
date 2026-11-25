// ============================================================================
// Magnetar Standard Library: Bot AI & Conversational Engine (lib/bot_ai.mg)
//
// Rule-based Natural Language Processing & Conversational Engine
// Features:
//   - Multi-language intent detection (Arabic & English)
//   - Natural math calculation (detects and evaluates math in sentences)
//   - Greetings, identity, social conversation
//   - Cybersecurity & programming knowledge base
//   - Smart contextual fallbacks
// ============================================================================

use "lib/string.mg";
use "lib/time.mg";

// Clean text: trim and handle basic spacing
fn _ai_clean_text(string text) -> string {
    return str_to_lower(str_trim(text));
}

// Check if string contains any of two keywords
fn _ai_has2(string s, string k1, string k2) -> bool {
    return str_contains(s, k1) || str_contains(s, k2);
}

// Check if string contains any of three keywords
fn _ai_has3(string s, string k1, string k2, string k3) -> bool {
    return str_contains(s, k1) || str_contains(s, k2) || str_contains(s, k3);
}

// Check if string contains any of four keywords
fn _ai_has4(string s, string k1, string k2, string k3, string k4) -> bool {
    return _ai_has2(s, k1, k2) || _ai_has2(s, k3, k4);
}

// Check if text is asking a question
fn _ai_is_question(string text) -> bool {
    if (str_contains(text, "?") || str_contains(text, "؟")) {
        return true;
    }
    if (str_starts_with(text, "ما ") || str_starts_with(text, "ماذا ") ||
        str_starts_with(text, "كيف ") || str_starts_with(text, "لماذا ") ||
        str_starts_with(text, "هل ") || str_starts_with(text, "من ") ||
        str_starts_with(text, "أين ") || str_starts_with(text, "كم ")) {
        return true;
    }
    return false;
}

// Try to evaluate a natural math expression inside text
// e.g. "احسب 5 + 3", "كم يساوي 20 * 4", "15 + 30"
fn _ai_try_math(string text) -> string {
    int n = len(text);
    char* p = cast<char*>(text);
    int op_pos = -1;
    char op_char = '+';

    for (int i = 0; i < n; i = i + 1) {
        int c = cast<int>(*(p + i)) & 255;
        if (c == 43 || c == 42 || c == 47) { // + * /
            op_pos = i;
            op_char = *(p + i);
            break;
        }
        // For minus '-', ensure it's an operator and not a dash/hyphen
        if (c == 45 && i > 0 && i < n - 1) {
            int prev = cast<int>(*(p + i - 1)) & 255;
            int next = cast<int>(*(p + i + 1)) & 255;
            if ((prev >= 48 && prev <= 57) || prev == 32) {
                if ((next >= 48 && next <= 57) || next == 32) {
                    op_pos = i;
                    op_char = '-';
                    break;
                }
            }
        }
    }

    if (op_pos < 0) { return ""; }

    // Scan backwards from op_pos to find the left number
    int left_end = op_pos - 1;
    while (left_end >= 0 && *(p + left_end) == 32) { left_end = left_end - 1; }
    if (left_end < 0) { return ""; }

    int left_start = left_end;
    while (left_start >= 0 && *(p + left_start) >= '0' && *(p + left_start) <= '9') {
        left_start = left_start - 1;
    }
    left_start = left_start + 1;
    if (left_start > left_end) { return ""; }

    // Scan forwards from op_pos to find the right number
    int right_start = op_pos + 1;
    while (right_start < n && *(p + right_start) == 32) { right_start = right_start + 1; }
    if (right_start >= n) { return ""; }

    int right_end = right_start;
    while (right_end < n && *(p + right_end) >= '0' && *(p + right_end) <= '9') {
        right_end = right_end + 1;
    }
    if (right_end <= right_start) { return ""; }

    string left_str = str_substr(text, left_start, left_end - left_start + 1);
    string right_str = str_substr(text, right_start, right_end - right_start);
    int left_val = str_to_int(left_str);
    int right_val = str_to_int(right_str);
    int ans = 0;
    string sym = "";

    if (op_char == '+') { ans = left_val + right_val; sym = "+"; }
    else if (op_char == '-') { ans = left_val - right_val; sym = "-"; }
    else if (op_char == '*') { ans = left_val * right_val; sym = "×"; }
    else if (op_char == '/') {
        if (right_val == 0) {
            return "العملية الرياضية غير ممكنة: لا يمكن القسمة على صفر! ⚠️";
        }
        ans = left_val / right_val;
        sym = "÷";
    }

    StringBuilder sb;
    sb.init(128);
    sb.append("🔢 حسبتها لك: ");
    sb.append(int_to_str(left_val));
    sb.append(" ");
    sb.append(sym);
    sb.append(" ");
    sb.append(int_to_str(right_val));
    sb.append(" = *");
    sb.append(int_to_str(ans));
    sb.append("* 🎯");
    string res = sb.to_string();
    sb.free_builder();
    return res;
}

// ============================================================================
// Main AI Response Generator
// ============================================================================

fn ai_chat_reply(string text, string user_name) -> string {
    if (text == null || len(text) == 0) {
        return "أهلاً بك! لم أسمع رسالتك بوضوح، هل يمكنك تكرارها؟ 😊";
    }

    string t = _ai_clean_text(text);
    string display_name = user_name;
    if (len(display_name) == 0) { display_name = "صديقي"; }

    // -------------------------------------------------------------
    // 1. Natural Math Check
    // -------------------------------------------------------------
    string math_ans = _ai_try_math(text);
    if (len(math_ans) > 0) {
        return math_ans;
    }

    // -------------------------------------------------------------
    // 2. Greetings
    // -------------------------------------------------------------
    if (_ai_has4(t, "السلام عليكم", "سلام عليكم", "وعليكم السلام", "سلام") ||
        _ai_has4(t, "مرحبا", "مرحباً", "أهلا", "اهلا") ||
        _ai_has4(t, "صباح الخير", "مساء الخير", "hello", "hi") ||
        str_contains(t, "hey")) {
        StringBuilder sb;
        sb.init(256);
        sb.append("وعليكم السلام وأهلاً وسهلاً بك يا *");
        sb.append(display_name);
        sb.append("*! 👋😊\nأنا مساعدك الذكي المبني بلغة Magnetar. كيف يمكنني مساعدتك اليوم؟");
        string reply = sb.to_string();
        sb.free_builder();
        return reply;
    }

    // -------------------------------------------------------------
    // 3. How are you / Status
    // -------------------------------------------------------------
    if (_ai_has4(t, "كيف حالك", "شخبارك", "شلونك", "واش راك") ||
        _ai_has4(t, "كيفك", "لاباس", "how are you", "how are u")) {
        StringBuilder sb;
        sb.init(256);
        sb.append("أنا بأفضل حال والحمد لله يا ");
        sb.append(display_name);
        sb.append("! ⚡🤖\nالخوادم تعمل بكفاءة 100% وبكامل طاقتي. وأنت، كيف تسير أمورك؟");
        string reply = sb.to_string();
        sb.free_builder();
        return reply;
    }

    // -------------------------------------------------------------
    // 4. Identity & Creator
    // -------------------------------------------------------------
    if (_ai_has4(t, "من انت", "من أنت", "عرف بنفسك", "ما اسمك") ||
        _ai_has3(t, "who are you", "what is your name", "what are you")) {
        return "🤖 أنا **Dragord**، بوت دردشة ومساعد ذكي مبني بالكامل بلغة البرمجة **Magnetar** ومترجم مباشرة إلى x86-64 Machine Code.\n\nأستطيع الإجابة على أسئلتك، حل المسائل الرياضية، تقديم معلومات عن البرمجة والأمن السيبراني، وأكثر! 🚀";
    }

    if (_ai_has4(t, "من صنعك", "من طورك", "من برمجك", "من انشأك") ||
        _ai_has3(t, "who made you", "who created you", "who built you")) {
        return "تمت برمجتي وتطويري بواسطة المبرمج **أسامة (Oussama)** 💻✨\nباستخدام لغة Magnetar الحديثة بدون أي مكتبات خارجية!";
    }

    // -------------------------------------------------------------
    // 5. Magnetar Language
    // -------------------------------------------------------------
    if (_ai_has3(t, "magnetar", "ماجنيتار", "لغة ماجنيتار") ||
        _ai_has2(t, "ماهي لغة", "ما هي لغة")) {
        return "🚀 **لغة Magnetar:**\nهي لغة برمجة قوية تُجمَّع مباشرة إلى لغة التجميع (x86-64 Assembly) وملفات ELF التنفيذية.\n\n✨ **أبرز مزاياها:**\n• لا تعتمد على libc بل تتصل بنواة Linux مباشرة (Syscalls)\n• تدعم الأنظمة والشبكات والـ TLS والتشفير المتقدم\n• سرعة خارقة في التنفيذ وتوزيع الذاكرة";
    }

    // -------------------------------------------------------------
    // 6. Cybersecurity & Ethical Hacking
    // -------------------------------------------------------------
    if (_ai_has4(t, "امن سيبراني", "أمن سيبراني", "cyber", "security") ||
        _ai_has2(t, "هاكر", "اختراق")) {
        return "🛡️ **الأمن السيبراني في Magnetar:**\nمشروع Falcon يحتوي على مكتبات أمنية مدمجة مثل:\n• `lib/security/sanitizer.mg` للحماية من ثغرات الحقن (SQLi/XSS/Command)\n• `lib/security/crypto_utils.mg` للتشفير والـ CSPRNG\n• `lib/security/packet_inspect.mg` لفحص الحزم وتحليل الهجمات\n• `lib/security/rate_limiter.mg` للحماية من هجمات DoS";
    }

    if (_ai_has3(t, "sql injection", "حقن sql", "sqli")) {
        return "💉 **ثغرة SQL Injection:**\nتحدث عندما يتم دمج نصوص المستخدم غير المعقمة داخل استعلامات SQL مباشرة.\n\n🛡️ **طرق الوقاية:**\n1. استخدام الاستعلامات المجهزة (Parameterized Queries / Prepared Statements)\n2. تعقيم المدخلات والتحقق من الأنواع\n3. تطبيق مبدأ الصلاحيات الأقل (Least Privilege)";
    }

    if (_ai_has3(t, "xss", "cross site", "حقن جافاسكريبت")) {
        return "🌐 **ثغرة XSS (Cross-Site Scripting):**\nتتيح للمهاجم تنفيذ كود JavaScript خبيث في متصفح الضحية لسرقة الجلسات أو التجسس.\n\n🛡️ **الوقاية:**\n1. تشفير مخرجات HTML (HTML Entity Encoding)\n2. تفعيل ترويسات Content Security Policy (CSP)\n3. تعيين HttpOnly للكوكيز الحساسة";
    }

    if (_ai_has3(t, "كلمة سر", "كلمة المرور", "password") || str_contains(t, "حماية حساب")) {
        return "🔑 **نصائح لكلمة مرور قوية:**\n• لا تقل عن 14 إلى 16 خانة\n• امزج بين الحروف الكبيرة والصغيرة والأرقام والرموز\n• لا تكرر كلمة المرور بين المواقع أبداً\n• فعّل المصادقة الثنائية (2FA) دائماً لحساباتك الحساسة";
    }

    // -------------------------------------------------------------
    // 7. Time & Date
    // -------------------------------------------------------------
    if (_ai_has4(t, "كم الساعة", "الوقت", "التاريخ", "ماهو اليوم") ||
        _ai_has2(t, "what time", "date today")) {
        DateTime dt;
        dt.now();
        StringBuilder sb;
        sb.init(256);
        sb.append("⏰ الوقت الحالي: *");
        sb.append(dt.format_time());
        sb.append(" UTC*\n📅 التاريخ: *");
        sb.append(dt.format_date());
        sb.append("* (");
        sb.append(dt.weekday_name());
        sb.append(")");
        string res = sb.to_string();
        sb.free_builder();
        return res;
    }

    // -------------------------------------------------------------
    // 8. Jokes & Fun
    // -------------------------------------------------------------
    if (_ai_has3(t, "نكتة", "نكته", "joke") || str_contains(t, "ضحكني")) {
        return "😄 **نكتة برمجية:**\nسألوا مبرمج: لماذا تفضل العمل في الظلام والليل دائماً؟\nفأجابهم: لأن البقّ (Bugs) ينجذب للضوء! 🐛💡😂";
    }

    // -------------------------------------------------------------
    // 9. Advice / Motivation
    // -------------------------------------------------------------
    if (_ai_has3(t, "نصيحة", "حكمة", "advice") || str_contains(t, "نصيحه")) {
        return "💡 **حكمة اليوم:**\n«البرمجة ليست مجرد كتابة كود، بل هي فن التفكير المنطقي وتحويل المشكلات المعقدة إلى حلول بسيطة وأنيقة.» — استمر في التعلم والإبداع! 🚀";
    }

    // -------------------------------------------------------------
    // 10. Gratitude & Goodbye
    // -------------------------------------------------------------
    if (_ai_has3(t, "شكرا", "شكراً", "thanks") || str_contains(t, "thank you")) {
        StringBuilder sb;
        sb.init(128);
        sb.append("على الرحب والسعة يا ");
        sb.append(display_name);
        sb.append("! دائماً في خدمتك وسعيد بالحديث معك ❤️");
        string reply = sb.to_string();
        sb.free_builder();
        return reply;
    }

    if (_ai_has4(t, "مع السلامة", "باي", "وداعا", "وداعاً") ||
        _ai_has2(t, "bye", "goodbye")) {
        return "في أمان الله وحفظه! أتمنى لك يوماً موفقاً ورائعاً 👋✨";
    }

    // -------------------------------------------------------------
    // 11. Intelligent Question & Conversational Fallback
    // -------------------------------------------------------------
    if (_ai_is_question(t)) {
        return "سؤالك ذكي ومثير للاهتمام! 🤔💡\nبما أنني نموذج محادثة وذكاء اصطناعي مدمج في Magnetar، أنصحك باستكشاف وتجربة أحد المواضيع التالية معي:\n• المسائل الحسابية المباشرة (مثل: `50 * 4`)\n• مفاهيم الأمن السيبراني (مثل: SQLi, XSS, الحماية)\n• لغة البرمجة Magnetar\n• أو كتابة /help لعرض قائمة الأوامر التفاعلية!";
    }

    // Default conversational AI response
    StringBuilder sb;
    sb.init(384);
    sb.append("فهمت ما تقصده يا ");
    sb.append(display_name);
    sb.append("! 🤖💬\nأنا أتعلم وأتطور باستمرار. يمكنك:\n• التحدث معي وسؤالي عن أي موضوع\n• إرسال أي عملية حسابية مثل: `25 * 4`\n• الاستفسار عن الأمن والبرمجة ولغة Magnetar\n• أو كتابة /help لعرض قائمة الأوامر.");
    string reply = sb.to_string();
    sb.free_builder();
    return reply;
}
