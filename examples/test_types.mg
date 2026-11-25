// examples/test_types.mg
// Comprehensive Falcon Types Verification Suite
use "lib/math.mg";
use "lib/stubs.mg";

fn main() -> void {
    print("=== FALCON TYPE SYSTEM INTEGRITY TEST ===\n\n");

    // 1. Primitive Scalar Types
    print("[1] Primitive Scalars:\n");
    int a = 42;
    float b = 3.14159;
    bool c = true;
    char d = 'F';
    string e = "Falcon Native Engine";
    
    print("  int: "); print(a); print("\n");
    print("  float: "); print(b); print("\n");
    print("  bool: "); print(c); print("\n");
    print("  char: "); print(d); print("\n");
    print("  string: "); print(e); print("\n\n");

    // 2. Systems and Size-specific Types
    print("[2] Systems/Size-specific Types:\n");
    byte b_val = 255;
    word w_val = 65535;
    dword dw_val = 123456789;
    qword qw_val = 9876543210;
    half h_val = 16;
    fixed<int, 4> f_val; 
    
    print("  byte: "); print(b_val); print("\n");
    print("  word: "); print(w_val); print("\n");
    print("  dword: "); print(dw_val); print("\n");
    print("  qword: "); print(qw_val); print("\n");
    print("  half: "); print(h_val); print("\n");
    print("  fixed-size array declared successfully!\n\n");

    // 3. Dynamic and Advanced Complex Types
    print("[3] Advanced Complex Types:\n");
    auto auto_int = 100;
    auto auto_float = 2.71828;
    any dynamic_val = 12345;
    
    print("  auto int: "); print(auto_int); print("\n");
    print("  auto float: "); print(auto_float); print("\n");
    print("  any dynamic: "); print(dynamic_val); print("\n\n");

    // 4. Memory Pointers, References & Qualifiers
    print("[4] Reference Pointers & Qualifiers:\n");
    int val = 88;
    int* p = &val;
    *p = 99;
    
    int* null_ptr = null;
    ref<int> r_ptr = &val;
    own<string> o_ptr = &e;
    raw raw_ptr = &val;

    print("  ptr dereference (*p = 99): "); print(val); print("\n");
    if (null_ptr == null) {
        print("  null pointer check passed!\n");
    }
    print("  ref<int> address: "); print(r_ptr); print("\n");
    print("  own<string> address: "); print(o_ptr); print("\n");
    print("  raw address: "); print(raw_ptr); print("\n\n");

    // 5. Array, Tuple, Map, Set, Range, Simd, Atom, Stream & Slices
    print("[5] Collection and Stream Types:\n");
    array<int, 4> my_arr;
    my_arr[0] = 10;
    my_arr[1] = 20;
    my_arr[2] = 30;
    my_arr[3] = 40;
    
    tuple<int, float, string> my_tup;
    my_tup._0 = 100;
    my_tup._1 = 3.14;
    my_tup._2 = "Falcon Tuple";
    
    map<string, int> my_map;
    set<int> my_set;
    slice<int> my_slice;
    
    simd<int, 4> my_simd;
    atom<int> my_atom;
    stream<int> my_stream;
    dyn<int> vec;

    print("  array[2] element: "); print(my_arr[2]); print("\n");
    print("  tuple fields: "); print(my_tup._0); print(", "); print(my_tup._1); print(", "); print(my_tup._2); print("\n");
    print("  simd<int,4> vector declaration successful!\n");
    print("  atomic counter declaration successful!\n");
    print("  stream pipeline declaration successful!\n\n");

    print("=== ALL FALCON TYPES VERIFIED SUCCESSFULY ===\n");
}
