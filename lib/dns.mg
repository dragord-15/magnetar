// ============================================================================
// Magnetar Standard Library: DNS Resolver (lib/dns.mg)
// Pure UDP DNS Client (IPv4 A-Record Resolution)
// ============================================================================

use "lib/net.mg";
use "lib/string.mg";

struct Ipv4Addr {
    int ip0;
    int ip1;
    int ip2;
    int ip3;
    bool valid;
};

// دالة داخلية لقراءة بايت واحد من الذاكرة كرقم موجب (0 إلى 255)
fn _dns_read_u8(char* ptr, int offset) -> int {
    int val = cast<int>(*(ptr + offset));
    if (val < 0) {
        val = val + 256;
    }
    return val;
}

// دالة داخلية لتحويل رقم (0-255) إلى نص داخل المخزن
fn _dns_byte_to_str(int num, char* buf, int offset) -> int {
    if (num == 0) {
        *(buf + offset) = '0';
        return offset + 1;
    }
    if (num >= 100) {
        *(buf + offset) = cast<char>((num / 100) + 48);
        offset = offset + 1;
        *(buf + offset) = cast<char>(((num / 10) % 10) + 48);
        offset = offset + 1;
        *(buf + offset) = cast<char>((num % 10) + 48);
        return offset + 1;
    }
    if (num >= 10) {
        *(buf + offset) = cast<char>((num / 10) + 48);
        offset = offset + 1;
        *(buf + offset) = cast<char>((num % 10) + 48);
        return offset + 1;
    }
    *(buf + offset) = cast<char>(num + 48);
    return offset + 1;
}

// تحويل Ipv4Addr إلى نص مقروء مثل "142.250.185.46"
fn dns_to_string(Ipv4Addr addr) -> string {
    if (!addr.valid) {
        return "0.0.0.0";
    }
    char* buf = alloc<char>(16);
    int pos = 0;

    pos = _dns_byte_to_str(addr.ip0, buf, pos);
    *(buf + pos) = '.';
    pos = pos + 1;

    pos = _dns_byte_to_str(addr.ip1, buf, pos);
    *(buf + pos) = '.';
    pos = pos + 1;

    pos = _dns_byte_to_str(addr.ip2, buf, pos);
    *(buf + pos) = '.';
    pos = pos + 1;

    pos = _dns_byte_to_str(addr.ip3, buf, pos);
    *(buf + pos) = 0;

    return cast<string>(buf);
}

// التحقق مما إذا كان النص المدخل هو عنوان IP جاهز (مثل "127.0.0.1")
fn dns_parse_ipv4(string ip_str) -> Ipv4Addr {
    Ipv4Addr addr;
    addr.ip0 = 0;
    addr.ip1 = 0;
    addr.ip2 = 0;
    addr.ip3 = 0;
    addr.valid = false;
    
    int* parts = alloc<int>(4);
    int part_idx = 0;
    int current_num = 0;
    int digits = 0;
    int s_len = len(ip_str);
    char* ptr = cast<char*>(ip_str);

    for (int i = 0; i < s_len; i = i + 1) {
        char c = *(ptr + i);
        if (c >= '0' && c <= '9') {
            current_num = (current_num * 10) + (cast<int>(c) - 48);
            digits = digits + 1;
            if (current_num > 255) {
                free(parts);
                return addr;
            }
        } else if (c == '.') {
            if (digits == 0 || part_idx >= 3) {
                free(parts);
                return addr;
            }
            *(parts + part_idx) = current_num;
            part_idx = part_idx + 1;
            current_num = 0;
            digits = 0;
        } else {
            free(parts);
            return addr;
        }
    }

    if (part_idx != 3 || digits == 0) {
        free(parts);
        return addr;
    }
    *(parts + 3) = current_num;

    addr.ip0 = *(parts + 0);
    addr.ip1 = *(parts + 1);
    addr.ip2 = *(parts + 2);
    addr.ip3 = *(parts + 3);
    addr.valid = true;
    free(parts);
    return addr;
}

// الدالة الرئيسية لتحويل اسم النطاق أو الـ IP إلى Ipv4Addr
// بناءاستعلام A قياسي وإرجاع طوله الكلي.
fn _dns_build_query(string hostname, char* packet) -> int {
    *(packet + 0) = 26; *(packet + 1) = 43; // Transaction ID (0x1A2B)
    *(packet + 2) = 1;  *(packet + 3) = 0;  // Standard Query + Recursion Desired
    *(packet + 4) = 0;  *(packet + 5) = 1;  // QDCOUNT = 1
    for (int i = 6; i < 12; i = i + 1) {
        *(packet + i) = 0;
    }

    int pos = 12;
    int label_len_pos = pos;
    pos = pos + 1;
    int current_len = 0;
    int d_len = len(hostname);
    char* d_ptr = cast<char*>(hostname);

    for (int i = 0; i < d_len; i = i + 1) {
        char c = *(d_ptr + i);
        if (c == '.') {
            *(packet + label_len_pos) = cast<char>(current_len);
            label_len_pos = pos;
            pos = pos + 1;
            current_len = 0;
        } else {
            *(packet + pos) = c;
            pos = pos + 1;
            current_len = current_len + 1;
        }
    }
    *(packet + label_len_pos) = cast<char>(current_len);
    *(packet + pos) = 0;
    pos = pos + 1;

    // QTYPE = A (1), QCLASS = IN (1)
    *(packet + pos) = 0; *(packet + pos + 1) = 1;
    *(packet + pos + 2) = 0; *(packet + pos + 3) = 1;
    pos = pos + 4;
    return pos;
}

// استعلام خادم DNS محدد. يعيد أول سجل A صالح.
fn dns_resolve_via(string hostname, int s0, int s1, int s2, int s3) -> Ipv4Addr {
    Ipv4Addr result;
    result.ip0 = 0; result.ip1 = 0; result.ip2 = 0; result.ip3 = 0;
    result.valid = false;

    int fd = net_socket_udp();
    if (fd < 0) {
        return result;
    }

    char* packet = alloc<char>(512);
    for (int i = 0; i < 512; i = i + 1) { *(packet + i) = 0; }
    int pos = _dns_build_query(hostname, packet);

    char* dns_server = net_create_ipv4_addr(s0, s1, s2, s3, 53);
    int sent = sys_sendto(fd, packet, pos, 0, dns_server, 16);
    free(dns_server);

    if (sent <= 0) {
        free(packet);
        sys_close(fd);
        return result;
    }

    char* resp = alloc<char>(2048);
    for (int i = 0; i < 2048; i = i + 1) { *(resp + i) = 0; }
    int recv_len = sys_recvfrom(fd, resp, 2048, 0, cast<char*>(0), cast<int*>(0));
    sys_close(fd);

    // يجب أن تطابق المعرّف والاستعلام. نفحص الإجابة (QR=1) وعدد الإجابات > 0.
    int flags0 = _dns_read_u8(resp, 2);
    int flags1 = _dns_read_u8(resp, 3);
    int answers_hi = _dns_read_u8(resp, 6);
    int answers_lo = _dns_read_u8(resp, 7);
    int answer_count = answers_hi * 256 + answers_lo;
    bool is_response = (flags0 & 128) != 0;

    if (recv_len > pos + 12 && is_response && answer_count > 0) {
        for (int i = pos; i < recv_len - 13; i = i + 1) {
            int type_hi  = _dns_read_u8(resp, i);
            int type_lo  = _dns_read_u8(resp, i + 1);
            int rdlen_hi = _dns_read_u8(resp, i + 8);
            int rdlen_lo = _dns_read_u8(resp, i + 9);

            // A record: TYPE=1, RDLENGTH=4
            if (type_hi == 0 && type_lo == 1 && rdlen_hi == 0 && rdlen_lo == 4) {
                result.ip0 = _dns_read_u8(resp, i + 10);
                result.ip1 = _dns_read_u8(resp, i + 11);
                result.ip2 = _dns_read_u8(resp, i + 12);
                result.ip3 = _dns_read_u8(resp, i + 13);
                result.valid = true;
                break;
            }
        }
    }

    free(packet);
    free(resp);
    return result;
}

// تحليل اسم عبر خادم DNS مكتوب كنص (مثل "8.8.8.8").
fn dns_resolve_with_server(string hostname, string server_ip) -> Ipv4Addr {
    Ipv4Addr direct = dns_parse_ipv4(hostname);
    if (direct.valid) {
        return direct;
    }
    Ipv4Addr server = dns_parse_ipv4(server_ip);
    if (!server.valid) {
        Ipv4Addr bad;
        bad.ip0 = 0; bad.ip1 = 0; bad.ip2 = 0; bad.ip3 = 0; bad.valid = false;
        return bad;
    }
    return dns_resolve_via(hostname, server.ip0, server.ip1, server.ip2, server.ip3);
}

// الدالة الرئيسية: تجرّب عدة خوادم DNS عامة حتى ينجح أحدها.
fn dns_resolve(string hostname) -> Ipv4Addr {
    Ipv4Addr direct = dns_parse_ipv4(hostname);
    if (direct.valid) {
        return direct;
    }

    Ipv4Addr result = dns_resolve_via(hostname, 1, 1, 1, 1);
    if (result.valid) { return result; }

    result = dns_resolve_via(hostname, 8, 8, 8, 8);
    if (result.valid) { return result; }

    result = dns_resolve_via(hostname, 9, 9, 9, 9);
    if (result.valid) { return result; }

    result = dns_resolve_via(hostname, 208, 67, 222, 222);
    if (result.valid) { return result; }

    return dns_resolve_via(hostname, 8, 8, 4, 4);
}
