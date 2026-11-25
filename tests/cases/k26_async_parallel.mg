fn main() {
    async { print("async\n"); }
    int s = await;
    print("after async\n");
    parallel { print("parallel\n"); }
    print("after parallel\n");
}
