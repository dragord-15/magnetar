extern fn audio_play(string track) -> void;
extern fn sql_connect(string url) -> int;

fn main() {
    audio_play("song.mg");
    print(sql_connect("db://x"));
    print("|\n");
}
