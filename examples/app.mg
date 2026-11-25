use "lib/net.mg";
use "lib/string.mg";
use "file.mg";
extern fn print_str(string s) -> void;



fn folder_ls()-> string {
    
    return "hello from here";
}


// دالة مساعدة للتحقق من وجود كلمة مفتاحية داخل رسالة المستخدم
fn contains_words(string text, string words) -> bool {
    int t_len = len(text);
    int w_len = len(words);
    if (w_len == 0 || t_len < w_len) {
        return false;
    }
    char* t_ptr = cast<char*>(text);
    char* w_ptr = cast<char*>(words);

    for (int i = 0; i <= t_len - w_len; i = i + 1) {
        bool matchs = true;
        for (int j = 0; j < w_len; j = j + 1) {
            if (*(t_ptr + i + j) != *(w_ptr + j)) {
                matchs = false;
                break;
            }
        }
        if (matchs) {
            return true;
        }
    }
    return false;
}

// عقل البوت: تحليل الرسالة وتوليد الرد المناسب
fn generate_bot_reply(string msg) -> string {
    if (msg == "hello" || msg == "hi" || msg == "مرحبا") {
        return "Bot: أهلاً بك! كيف يمكنني مساعدتك اليوم؟";
    }
    if (msg == "name" || msg == "اسمك") {
        return "Bot: أنا بوت محادثة مبني بالكامل بلغة Magnetar.";
    }
    if (msg == "help" || msg == "مساعدة") {
        return "Bot: جرب أن تسألني عن (اسمك) أو قل (مرحبا)، أو اكتب exit للخروج.";
    }
    if (msg == "status" || msg == "حالتك") {
        return "Bot: أعمل بكامل طاقتي وبدون انقطاع على خادم لينكس!";
    }
    if (msg == "ls" ){
        return folder_ls();
    }
    return "Bot: رسالة مثيرة للاهتمام! اكتب (help) لمعرفة الأوامر التي أفهمها.";
}


fn main() -> int {
    TcpServer server;
    int port = 5555;

    if (!server.start(port, 10)) {
        print_str("Failed to start Chat Bot server on port 5555\n");
        return 1;
    }

    print_str("Magnetar Chat Bot is online at 127.0.0.1:5555...\n");

    // حلقة خارجية: تجعل البوت يعمل للأبد ويستقبل مستخدمين جدد إذا انقطع الاتصال
    while (true) {
        int client_fd = server.accept_connection();
        if (client_fd < 0) {
            continue;
        }

        print_str("New user joined the chat!\n");
        net_send_str(client_fd, "Bot: تم الاتصال بالبوت بنجاح! اكتب رسالتك (أو exit للخروج):\n");

        // حلقة داخلية: محادثة مستمرة مع المستخدم الحالي بدون انقطاع
        while (true) {
            string user_msg = net_recv(client_fd, 1024);

            // إذا أغلق المستخدم النافذة فجأة (0 بايت)
            if (len(user_msg) == 0) {
                print_str("User disconnected.\n");
                break;
            }

            print_str("User: ");
            print_str(user_msg);
            print_str("\n");

            // التحقق من طلب الخروج
            if (contains_words(user_msg, "exit")) {
                net_send_str(client_fd, "Bot: إلى اللقاء! تم إنهاء المحادثة.\n");
                print_str("User exited the chat.\n");
                break;
            }

            // إرسال رد البوت الفوري
            string reply = generate_bot_reply(user_msg);
            reply = str_concat(reply, "\n");
            net_send_str(client_fd, reply);
        }

        net_close(client_fd);
    }

    server.stop();
    return 0;
}

