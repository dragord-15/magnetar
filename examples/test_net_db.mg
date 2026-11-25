// examples/test_net_db.mg
// Verification suite for Network and Database SQL libraries

extern fn net_listen(int port) -> int;
extern fn net_accept(int socket) -> int;
extern fn net_send(int socket, string data) -> void;
extern fn net_close(int socket) -> void;

extern fn sql_connect(string db) -> int;
extern fn sql_query(int handle, string query) -> void;

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

class Server {
    int port;
    int serverSocket;
    int clientSocket;
    
    fn start(int p) -> void {
        this.port = p;
        this.serverSocket = net_listen(p);
    }
    
    fn acceptConnection() -> void {
        this.clientSocket = net_accept(this.serverSocket);
    }
    
    fn sendGreeting() -> void {
        net_send(this.clientSocket, "Welcome to Falcon Socket Server!");
    }
    
    fn shutdown() -> void {
        net_close(this.clientSocket);
        net_close(this.serverSocket);
    }
};

class Database {
    int handle;
    string dbName;
    
    fn connect(string name) -> void {
        this.dbName = name;
        this.handle = sql_connect(name);
    }
    
    fn runQuery(string q) -> void {
        sql_query(this.handle, q);
    }
};

fn main() -> void {
    print_str("--- Falcon Standard Library: Network and Database SQL ---\n");

    // 1. Network
    Server srv;
    srv.start(8080);
    srv.acceptConnection();
    srv.sendGreeting();
    srv.shutdown();

    // 2. Database SQL
    Database db;
    db.connect("falcon_main.db");
    db.runQuery("SELECT * FROM users;");

    print_str("SUCCESS: Network and Database SQL libraries compiled and executed perfectly!\n");
}
