use "../../lib/algorithm.mg";
use "../../lib/hashmap.mg";

extern fn print_str(string s) -> void;

fn show_arr(int* a, int n) -> void {
    int i = 0;
    while (i < n) { print(a[i]); print(","); i = i + 1; }
    print_str("\n");
}

fn test_algorithm() -> void {
    int src_arr[6] = {5, 3, 9, 1, 7, 3};
    int work[6];
    int i = 0;

    print_str("search|");
    print(linear_search(cast<int*>(src_arr), 6, 7)); print(",");
    print(linear_search(cast<int*>(src_arr), 6, 42)); print(",");
    int sorted[6] = {1, 3, 3, 5, 7, 9};
    print(binary_search(cast<int*>(sorted), 6, 5)); print(",");
    print(binary_search(cast<int*>(sorted), 6, 4)); print(",");
    print(lower_bound(cast<int*>(sorted), 6, 3)); print(",");
    print(upper_bound(cast<int*>(sorted), 6, 3)); print(",");
    print(lower_bound(cast<int*>(sorted), 6, 6)); print(",");
    print(upper_bound(cast<int*>(sorted), 6, 9)); print_str("\n");

    print_str("sorts|");
    copy_array(cast<int*>(src_arr), cast<int*>(work), 6); insertion_sort(cast<int*>(work), 6); show_arr(cast<int*>(work), 6);
    copy_array(cast<int*>(src_arr), cast<int*>(work), 6); heap_sort(cast<int*>(work), 6); show_arr(cast<int*>(work), 6);
    copy_array(cast<int*>(src_arr), cast<int*>(work), 6); quick_sort(cast<int*>(work), 6); show_arr(cast<int*>(work), 6);
    copy_array(cast<int*>(src_arr), cast<int*>(work), 6); merge_sort(cast<int*>(work), 6); show_arr(cast<int*>(work), 6);
    copy_array(cast<int*>(src_arr), cast<int*>(work), 6); sort(cast<int*>(work), 6); print(is_sorted(cast<int*>(work), 6)); print_str("\n");
    copy_array(cast<int*>(src_arr), cast<int*>(work), 6); sort_stable(cast<int*>(work), 6); print(is_sorted(cast<int*>(work), 6)); print_str("\n");

    print_str("utils|");
    print(array_min(cast<int*>(src_arr), 6)); print(",");
    print(array_max(cast<int*>(src_arr), 6)); print(",");
    print(min_index(cast<int*>(src_arr), 6)); print(",");
    print(max_index(cast<int*>(src_arr), 6)); print(",");
    print(array_sum(cast<int*>(src_arr), 6)); print(",");
    print(count_value(cast<int*>(src_arr), 6, 3)); print(",");
    print(array_equals(cast<int*>(src_arr), cast<int*>(src_arr), 6)); print(",");
    print(clamp_int(11, 0, 10)); print(",");
    print(clamp_int(0 - 5, 0, 10)); print_str("\n");

    int u[5] = {1, 1, 2, 2, 3};
    print_str("unique|");
    int un = unique_sorted(cast<int*>(u), 5); print(un); print("|"); show_arr(cast<int*>(u), un);

    int r[5] = {1, 2, 3, 4, 5};
    print_str("rotate|");
    rotate_left(cast<int*>(r), 5, 2); show_arr(cast<int*>(r), 5);
    rotate_right(cast<int*>(r), 5, 2); show_arr(cast<int*>(r), 5);
    reverse(cast<int*>(r), 5); show_arr(cast<int*>(r), 5);

    int d[6] = {1, 3, 3, 5, 7, 9};
    sort_desc(cast<int*>(d), 6);
    print_str("desc|"); show_arr(cast<int*>(d), 6);
    print(binary_search_desc(cast<int*>(d), 6, 5)); print(",");
    print(binary_search_desc(cast<int*>(d), 6, 4)); print_str("\n");

    int f[4];
    fill(cast<int*>(f), 4, 7); print_str("fill|"); show_arr(cast<int*>(f), 4);
    copy_array(cast<int*>(src_arr), cast<int*>(work), 6); print_str("copy|"); show_arr(cast<int*>(work), 6);

    IntList l; l.init(4);
    l.push(5); l.push(1); l.push(4); l.push(2); l.push(3);
    print_str("list|");
    print(intlist_is_sorted(&l)); print(",");
    intlist_sort(&l); show_arr(l.data, l.length);
    print(intlist_is_sorted(&l)); print(",");
    print(intlist_binary_search(&l, 4)); print(",");
    print(intlist_lower_bound(&l, 3)); print(",");
    print(intlist_upper_bound(&l, 3)); print(",");
    print(intlist_linear_search(&l, 9)); print(",");
    print(intlist_min(&l)); print(",");
    print(intlist_max(&l)); print(",");
    print(intlist_sum(&l)); print(",");
    print(intlist_count(&l, 3)); print(",");
    print(intlist_contains(&l, 4)); print(",");
    print(intlist_index_of(&l, 5)); print_str("\n");
    print(intlist_remove_value(&l, 2)); print(",");
    print(intlist_remove_value(&l, 42)); print(",");
    print(intlist_push_unique(&l, 3)); print(",");
    print(intlist_push_unique(&l, 9)); print(",");
    print(l.length); print_str("\n");
    intlist_sort(&l); intlist_unique_sorted(&l); show_arr(l.data, l.length);
    intlist_reverse(&l); show_arr(l.data, l.length);
    intlist_sort_desc(&l); show_arr(l.data, l.length);
    intlist_fill(&l, 8); show_arr(l.data, l.length);
    IntList c; c.init(4); intlist_copy(&l, &c); show_arr(c.data, c.length);
    l.free_list(); c.free_list();
}

fn test_hashmap() -> void {
    IntIntMap m; m.init(2);
    int i = 0;
    while (i < 20) { m.put(i, i * 10); i = i + 1; }
    int* keys = alloc<int>(64);
    int nk = intintmap_keys(&m, keys);
    int sum = 0; i = 0; while (i < nk) { sum = sum + keys[i]; i = i + 1; }
    print_str("iimap|");
    print(m.size()); print(",");
    print(nk); print(",");
    print(sum); print(",");
    print(m.get(0, 0 - 1)); print(",");
    print(m.get(7, 0 - 1)); print(",");
    print(m.get(19, 0 - 1)); print(",");
    print(m.get(50, 0 - 1)); print(",");
    print(m.has(13)); print(",");
    print(m.has(50)); print_str("\n");
    m.put(7, 777);
    print_str("overwrite|");
    print(m.size()); print(",");
    print(m.get(7, 0 - 1)); print_str("\n");
    print(m.remove(3)); print(",");
    print(m.remove(4)); print(",");
    print(m.remove(3)); print(",");
    print(m.size()); print(",");
    print(m.has(3)); print(",");
    print(m.get(4, 0 - 1)); print_str("\n");
    m.put(3, 30); m.put(4, 40);
    print_str("tomb|");
    print(m.size()); print(",");
    print(m.get(3, 0 - 1)); print(",");
    print(m.get(4, 0 - 1)); print_str("\n");
    m.clear();
    print_str("clear|");
    print(m.size()); print(",");
    print(m.has(0)); print(",");
    print(m.get(0, 0 - 1)); print_str("\n");
    m.free_map();
    free(keys);

    IntIntMap big; big.init(8);
    i = 0; while (i < 100) { big.put(i, i); i = i + 1; }
    i = 0; while (i < 100) { big.remove(i); i = i + 2; }
    i = 0; while (i < 100) { big.put(i, i); i = i + 1; }
    int good = 0; i = 0; while (i < 100) { if (big.get(i, 0 - 1) == i) { good = good + 1; } i = i + 1; }
    print_str("stress|"); print(big.size()); print(","); print(good); print_str("\n");
    big.free_map();

    StrIntMap sm; sm.init(4);
    sm.put("apple", 1); sm.put("banana", 2); sm.put("cherry", 3); sm.put("date", 4);
    string* skeys = alloc<string>(32);
    int sn = strintmap_keys(&sm, skeys);
    print_str("simap|");
    print(sm.size()); print(",");
    print(sm.get("banana", 0 - 1)); print(",");
    print(sm.has("pear")); print(",");
    print(sn); print_str("\n");
    sm.put("banana", 20);
    print_str("siow|");
    print(sm.size()); print(",");
    print(sm.get("banana", 0 - 1)); print_str("\n");
    print(sm.remove("apple")); print(",");
    print(sm.has("apple")); print(",");
    print(sm.get("apple", 0 - 1)); print(",");
    print(sm.size()); print_str("\n");
    sm.free_map(); free(skeys);

    StrStrMap cfg; cfg.init(4);
    cfg.put("name", "magnetar"); cfg.put("lang", "mg");
    string* ckeys = alloc<string>(32);
    int cn = strstrmap_keys(&cfg, ckeys);
    print_str("ssmap|");
    print(cfg.size()); print(",");
    print_str(cfg.get("name", "?")); print(",");
    print_str(cfg.get("missing", "?")); print(",");
    print(cn); print_str("\n");
    cfg.put("name", "falcon");
    print_str(cfg.get("name", "?")); print(",");
    print(cfg.remove("lang")); print(",");
    print(cfg.has("lang")); print(",");
    print(cfg.size()); print_str("\n");
    cfg.free_map(); free(ckeys);

    IntSet is; is.init(4);
    print_str("iset|");
    print(is.add(1)); print(",");
    print(is.add(2)); print(",");
    print(is.add(2)); print(",");
    print(is.add(3)); print(",");
    print(is.size()); print(",");
    print(is.has(2)); print(",");
    print(is.remove(2)); print(",");
    print(is.has(2)); print(",");
    print(is.add(2)); print(",");
    int* ivals = alloc<int>(16);
    int ivn = intset_values(&is, ivals); print(ivn); print_str("\n");
    is.clear(); print(is.size()); print(","); print(is.has(1)); print_str("\n");
    is.free_set(); free(ivals);

    StrSet ss; ss.init(4);
    string* svals = alloc<string>(16);
    print_str("sset|");
    print(ss.add("x")); print(",");
    print(ss.add("y")); print(",");
    print(ss.add("x")); print(",");
    print(ss.size()); print(",");
    print(ss.has("y")); print(",");
    print(ss.remove("x")); print(",");
    print(ss.has("x")); print(",");
    int svn = strset_values(&ss, svals); print(svn); print_str("\n");
    ss.free_set(); free(svals);
}

fn main() -> int {
    test_algorithm();
    test_hashmap();
    return 0;
}
