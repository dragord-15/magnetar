// ============================================================================
// Magnetar Security Library: Network Packet Inspection & IDS Heuristics
// File: lib/security/packet_inspect.mg
// Defensive network packet parsing and port-scan/anomaly detection
// ============================================================================

use "lib/string.mg";

// TCP Flag Constants
const int TCP_FLAG_FIN = 1;  // 0x01
const int TCP_FLAG_SYN = 2;  // 0x02
const int TCP_FLAG_RST = 4;  // 0x04
const int TCP_FLAG_PSH = 8;  // 0x08
const int TCP_FLAG_ACK = 16; // 0x10
const int TCP_FLAG_URG = 32; // 0x20

// Protocol Constants
const int PROTO_ICMP = 1;
const int PROTO_TCP  = 6;
const int PROTO_UDP  = 17;

struct DecodedIPv4 {
    int version;
    int ihl;
    int total_length;
    int ttl;
    int protocol;
    int src_ip0;
    int src_ip1;
    int src_ip2;
    int src_ip3;
    int dst_ip0;
    int dst_ip1;
    int dst_ip2;
    int dst_ip3;
}

struct DecodedTCP {
    int src_port;
    int dst_port;
    int seq_num;
    int ack_num;
    int data_offset;
    int flags;
    int window_size;
}

// Parses raw IPv4 packet buffer
fn packet_decode_ipv4(char* raw_pkt, int pkt_len) -> DecodedIPv4 {
    let hdr: DecodedIPv4;
    if (raw_pkt == null || pkt_len < 20) {
        hdr.version = 0;
        return hdr;
    }
    
    let b0 = cast<int>(raw_pkt[0]) & 255;
    hdr.version = b0 >> 4;
    hdr.ihl = (b0 & 15) * 4; // header length in bytes
    
    let len_hi = cast<int>(raw_pkt[2]) & 255;
    let len_lo = cast<int>(raw_pkt[3]) & 255;
    hdr.total_length = (len_hi << 8) | len_lo;
    
    hdr.ttl = cast<int>(raw_pkt[8]) & 255;
    hdr.protocol = cast<int>(raw_pkt[9]) & 255;
    
    hdr.src_ip0 = cast<int>(raw_pkt[12]) & 255;
    hdr.src_ip1 = cast<int>(raw_pkt[13]) & 255;
    hdr.src_ip2 = cast<int>(raw_pkt[14]) & 255;
    hdr.src_ip3 = cast<int>(raw_pkt[15]) & 255;
    
    hdr.dst_ip0 = cast<int>(raw_pkt[16]) & 255;
    hdr.dst_ip1 = cast<int>(raw_pkt[17]) & 255;
    hdr.dst_ip2 = cast<int>(raw_pkt[18]) & 255;
    hdr.dst_ip3 = cast<int>(raw_pkt[19]) & 255;
    
    return hdr;
}

// Parses TCP header following IPv4 header
fn packet_decode_tcp(char* raw_pkt, int pkt_len, int ip_ihl) -> DecodedTCP {
    let tcp: DecodedTCP;
    if (raw_pkt == null || pkt_len < ip_ihl + 20) {
        tcp.src_port = 0;
        tcp.dst_port = 0;
        tcp.flags = 0;
        return tcp;
    }
    
    let off = ip_ihl;
    let sp_hi = cast<int>(raw_pkt[off + 0]) & 255;
    let sp_lo = cast<int>(raw_pkt[off + 1]) & 255;
    tcp.src_port = (sp_hi << 8) | sp_lo;
    
    let dp_hi = cast<int>(raw_pkt[off + 2]) & 255;
    let dp_lo = cast<int>(raw_pkt[off + 3]) & 255;
    tcp.dst_port = (dp_hi << 8) | dp_lo;
    
    let b12 = cast<int>(raw_pkt[off + 12]) & 255;
    tcp.data_offset = (b12 >> 4) * 4;
    
    let b13 = cast<int>(raw_pkt[off + 13]) & 255;
    tcp.flags = b13 & 63; // 6 standard TCP flags
    
    let w_hi = cast<int>(raw_pkt[off + 14]) & 255;
    let w_lo = cast<int>(raw_pkt[off + 15]) & 255;
    tcp.window_size = (w_hi << 8) | w_lo;
    
    return tcp;
}

// ----------------------------------------------------------------------------
// Intrusion Detection System (IDS) Heuristics
// ----------------------------------------------------------------------------

// Detects NULL scan (nmap -sN): TCP packet with zero flags set
fn ids_is_null_scan(int flags) -> bool {
    return flags == 0;
}

// Detects XMAS scan (nmap -sX): FIN + PSH + URG flags all set
fn ids_is_xmas_scan(int flags) -> bool {
    let xmas_mask = TCP_FLAG_FIN | TCP_FLAG_PSH | TCP_FLAG_URG;
    return (flags & xmas_mask) == xmas_mask;
}

// Detects SYN Stealth scan (nmap -sS): SYN set without ACK
fn ids_is_syn_scan(int flags) -> bool {
    return ((flags & TCP_FLAG_SYN) != 0) && ((flags & TCP_FLAG_ACK) == 0);
}

// Detects FIN scan (nmap -sF): FIN set without ACK
fn ids_is_fin_scan(int flags) -> bool {
    return ((flags & TCP_FLAG_FIN) != 0) && ((flags & TCP_FLAG_ACK) == 0);
}

// Detects LAND Attack DoS: Source IP equals Destination IP and Source Port equals Destination Port
fn ids_is_land_attack(DecodedIPv4 ip, DecodedTCP tcp) -> bool {
    let ip_match = (ip.src_ip0 == ip.dst_ip0) && (ip.src_ip1 == ip.dst_ip1) &&
                   (ip.src_ip2 == ip.dst_ip2) && (ip.src_ip3 == ip.dst_ip3);
    let port_match = (tcp.src_port == tcp.dst_port) && (tcp.src_port != 0);
    return ip_match && port_match;
}

// Checks if packet TTL is suspiciously low (< 3), common in evasive TTL-expiry attacks
fn ids_is_suspicious_ttl(int ttl) -> bool {
    return ttl > 0 && ttl <= 2;
}

