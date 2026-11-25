// MDE hello client - tests IPC against compositor
// Build: ./magc mde/apps/hello/main.mg -o build/mde-hello

use "lib/ipc.mg";
use "lib/mde_ipc.mg";
use "lib/json.mg";

extern fn print_str(string s) -> void;

fn main() -> int {
    string sock = "/tmp/mde-compositor.sock";
    int fd = ipc_client_connect(sock);
    if (fd < 0) { print_str("connect failed\n"); return 1; }
    ipc_send_line(fd, mde_req(1, "hello", "{\"role\":\"app\",\"name\":\"mde-hello\"}"));
    char* buf = alloc<char>(4096);
    int n = ipc_recv_line(fd, buf, 4096);
    if (n > 0) { print_str(cast<string>(buf)); print_str("\n"); }
    ipc_send_line(fd, mde_req(2, "ping", "{}"));
    n = ipc_recv_line(fd, buf, 4096);
    if (n > 0) { print_str(cast<string>(buf)); print_str("\n"); }
    ipc_close(fd);
    return 0;
}
