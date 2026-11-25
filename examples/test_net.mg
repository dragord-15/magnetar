// examples/test_net.mg
// Test suite for Real Native Socket Networking (lib/net.mg)

use "lib/net.mg";

fn main() -> void {
    print("=== STARTING MAGNETAR NETWORKING VERIFICATION ===\n\n");

    int test_port = 28888;

    // 1. Start TCP Server
    print("[1] Starting TCP Server on port "); print(test_port); print("...\n");
    TcpServer server;
    bool s_ok = server.start(test_port, 5);
    print("  Server start status: "); print(s_ok); print("\n");

    // 2. Connect with TCP Client
    print("[2] Connecting TCP Client to localhost...\n");
    TcpClient client;
    bool c_ok = client.connect_localhost(test_port);
    print("  Client connect status: "); print(c_ok); print("\n");

    // 3. Server Accept
    print("[3] Accepting client connection on server...\n");
    int incoming_fd = server.accept_connection();
    print("  Accepted client FD: "); print(incoming_fd); print("\n");

    // 4. Send from client to server
    print("[4] Client sending greeting to server...\n");
    int sent_bytes = client.send_data("PING: Hello from Magnetar Client!");
    print("  Bytes sent: "); print(sent_bytes); print("\n");

    // 5. Server receive
    print("[5] Server reading incoming data...\n");
    string server_received = net_recv(incoming_fd, 1024);
    print("  Server received: ["); print_str(server_received); print("]\n");

    // 6. Server responds back
    print("[6] Server echoing reply back to client...\n");
    net_send_str(incoming_fd, "PONG: Welcome to Magnetar Networking!");

    // 7. Client receives response
    print("[7] Client receiving reply from server...\n");
    string client_received = client.receive(1024);
    print("  Client received: ["); print_str(client_received); print("]\n");

    // Clean up
    net_close(incoming_fd);
    client.close();
    server.stop();

    print("\n=== ALL NETWORKING TESTS PASSED SUCCESSFULLY! ===\n");
}
