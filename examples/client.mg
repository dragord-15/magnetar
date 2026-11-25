use "lib/net.mg";
use "lib/string.mg";

extern fn print_str(string s) -> void;
extern fn sys_read(int fd, char* buf, int count) -> int;

// دالة لقراءة سطر يكتبه المستخدم في الطرفية
fn read_line() -> string {
    char* buf = alloc<char>(512);
    int bytes = sys_read(0, buf, 511); // 0 = STDIN (لوحة المفاتيح)
    if (bytes > 0) {
        // إزالة حرف السطر الجديد '\n' من نهاية الإدخال
        if (*(buf + bytes - 1) == 10) {
            *(buf + bytes - 1) = 0;
        } else {
            *(buf + bytes) = 0;
        }
        return cast<string>(buf);
    }
    free(buf);
    return "";
}

fn main() -> int {
    TcpClient client;
    if (!client.connect_localhost(5555)) {
        print_str("Could not connect to Chat Bot!\n");
        return 1;
    }

    // قراءة رسالة الترحيب الأولى من البوت
    string welcome = client.receive(1024);
    print_str(welcome);

    // حلقة المحادثة المستمرة
    while (true) {
        print_str("You > ");
        string input = read_line();

        if (len(input) == 0) {
            continue;
        }

        // إرسال الرسالة للبوت
        client.send_data(input);

        // استقبال رد البوت
        string bot_reply = client.receive(1024);
        if (len(bot_reply) == 0) {
            print_str("Disconnected from Bot.\n");
            break;
        }

        print_str(bot_reply);

        // الخروج إذا كتب المستخدم exit
        if (len(input) == 4 && *(cast<char*>(input)) == 101 && *(cast<char*>(input) + 1) == 120) {
            break;
        }
    }

    client.close();
    return 0;
}

