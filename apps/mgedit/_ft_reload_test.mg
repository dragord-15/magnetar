use "file.mg";
use "view.mg";
use "filetree.mg";
extern fn print_int(int n) -> void;
fn main() -> int {
    view_init();
    ft_init();
    print_str("T init "); print_int(ft_count()); print_str("\n");
    ft_set_dir("/tmp/opencode");
    ft_scan();
    print_str("T after "); print_int(ft_count()); print_str("\n");
    return 0;
}
