module types;
extern fn exit(int code) -> int;

const int TYPE_INT     = 0;
const int TYPE_FLOAT   = 1;
const int TYPE_BOOL    = 2;
const int TYPE_STRING  = 3;
const int TYPE_VOID    = 4;
const int TYPE_STRUCT  = 5;
const int TYPE_CLASS   = 6;
const int TYPE_ENUM    = 7;
const int TYPE_UNKNOWN = 8;

// هيكل DataType: حقلان بـ 8 بايت لكل منهما
// [offset 0] = type_class
// [offset 8] = size_val
fn DataType_create(int tclass, int sz) -> int {
    int* dt = alloc<int>(2);
    if (dt == 0) { exit(1); }
    *dt = tclass;
    int* size_f = dt + 8;
    *size_f = sz;
    return dt;
}

fn DataType_get_class(int dt_raw) -> int {
    if (dt_raw == 0) { return TYPE_UNKNOWN; }
    int* dt = dt_raw;
    return *dt;
}

fn DataType_get_size(int dt_raw) -> int {
    if (dt_raw == 0) { return 0; }
    int* size_f = dt_raw + 8;
    return *size_f;
}

fn DataType_free(int dt_raw) -> void {
    if (dt_raw != 0) { free(dt_raw); }
}

fn DataType_create_int() -> int {
    return DataType_create(TYPE_INT, 8);
}

fn DataType_create_float() -> int {
    return DataType_create(TYPE_FLOAT, 8);
}

fn DataType_create_bool() -> int {
    return DataType_create(TYPE_BOOL, 1);
}

fn DataType_create_string() -> int {
    return DataType_create(TYPE_STRING, 8);
}

fn DataType_create_void() -> int {
    return DataType_create(TYPE_VOID, 0);
}

fn DataType_print_class(int tclass) -> void {
    if (tclass == TYPE_INT)    { print "int";    return; }
    if (tclass == TYPE_FLOAT)  { print "float";  return; }
    if (tclass == TYPE_BOOL)   { print "bool";   return; }
    if (tclass == TYPE_STRING) { print "string"; return; }
    if (tclass == TYPE_VOID)   { print "void";   return; }
    if (tclass == TYPE_STRUCT) { print "struct"; return; }
    if (tclass == TYPE_CLASS)  { print "class";  return; }
    if (tclass == TYPE_ENUM)   { print "enum";   return; }
    print "unknown";
}
module symbols;
extern fn exit(int code) -> int;

// هيكل Symbol (4 حقول × 8 بايت = 32 بايت):
// [offset  0] = key_id    (int)
// [offset  8] = type_ptr  (int)
// [offset 16] = scope     (int)
// [offset 24] = next_ptr  (int)

// هيكل SymbolTable (3 حقول × 8 بايت = 24 بايت):
// [offset  0] = bcount    (int)
// [offset  8] = cur_scope (int)
// [offset 16] = buckets   (int - مؤشر لمصفوفة)

const int DEFAULT_BUCKETS = 64;

fn hash_key(int key, int bcount) -> int {
    int h = key;
    if (h < 0) { h = h * -1; }
    int idx = h - ((h / bcount) * bcount);
    return idx;
}

fn SymbolTable_create(int size) -> int {
    int bcount = size;
    if (bcount <= 0) { bcount = DEFAULT_BUCKETS; }

    // تخصيص مصفوفة المجموعات (bcount حقل بـ 8 بايت)
    int* buckets = alloc<int>(bcount);
    if (buckets == 0) { exit(1); }

    // تهيئة جميع الخانات بـ 0
    int i = 0;
    while (i < bcount) {
        int* slot = buckets + (i * 8);
        *slot = 0;
        i = i + 1;
    }

    // تخصيص هيكل الجدول
    int* tbl = alloc<int>(3);
    if (tbl == 0) { exit(1); }

    *tbl = bcount;
    int* sf = tbl + 8;
    *sf = 0;
    int* bf = tbl + 16;
    *bf = buckets;

    return tbl;
}

fn SymbolTable_enter_scope(int tbl_raw) -> void {
    if (tbl_raw == 0) { return; }
    int* sf = tbl_raw + 8;
    *sf = *sf + 1;
}

fn SymbolTable_exit_scope(int tbl_raw) -> void {
    if (tbl_raw == 0) { return; }

    int* sf      = tbl_raw + 8;
    int  scope   = *sf;
    int* bcf     = tbl_raw;
    int  bcount  = *bcf;
    int* bpf     = tbl_raw + 16;
    int  buckets = *bpf;

    int i = 0;
    while (i < bcount) {
        int* slot_ptr = buckets + (i * 8);
        int  curr     = *slot_ptr;
        int  prev     = 0;
        while (curr != 0) {
            int* scope_f = curr + 16;
            int  sym_sc  = *scope_f;
            int* next_f  = curr + 24;
            int  nxt     = *next_f;
            if (sym_sc == scope) {
                if (prev != 0) {
                    int* pnf = prev + 24;
                    *pnf = nxt;
                } else {
                    *slot_ptr = nxt;
                }
                free(curr);
                curr = nxt;
            } else {
                prev = curr;
                curr = nxt;
            }
        }
        i = i + 1;
    }
    *sf = scope - 1;
}

fn SymbolTable_insert(int tbl_raw, int key_id, int type_ptr) -> void {
    if (tbl_raw == 0) { return; }

    int* bcf     = tbl_raw;
    int  bcount  = *bcf;
    int* sf      = tbl_raw + 8;
    int  scope   = *sf;
    int* bpf     = tbl_raw + 16;
    int  buckets = *bpf;

    int  idx      = hash_key(key_id, bcount);
    int* slot_ptr = buckets + (idx * 8);
    int  old_hd   = *slot_ptr;

    // تخصيص رمز جديد (4 حقول)
    int* sym = alloc<int>(4);
    if (sym == 0) { exit(1); }

    *sym = key_id;
    int* tf = sym + 8;   *tf = type_ptr;
    int* scf = sym + 16; *scf = scope;
    int* nf = sym + 24;  *nf = old_hd;

    *slot_ptr = sym;
}

fn SymbolTable_lookup(int tbl_raw, int key_id) -> int {
    if (tbl_raw == 0) { return 0; }

    int* bcf     = tbl_raw;
    int  bcount  = *bcf;
    int* bpf     = tbl_raw + 16;
    int  buckets = *bpf;

    int  idx      = hash_key(key_id, bcount);
    int* slot_ptr = buckets + (idx * 8);
    int  curr     = *slot_ptr;

    while (curr != 0) {
        int* kf     = curr;
        int  sym_k  = *kf;
        if (sym_k == key_id) { return curr; }
        int* nf = curr + 24;
        curr = *nf;
    }
    return 0;
}

fn SymbolTable_free(int tbl_raw) -> void {
    if (tbl_raw == 0) { return; }

    int* bcf     = tbl_raw;
    int  bcount  = *bcf;
    int* bpf     = tbl_raw + 16;
    int  buckets = *bpf;

    int i = 0;
    while (i < bcount) {
        int* slot_ptr = buckets + (i * 8);
        int  curr     = *slot_ptr;
        while (curr != 0) {
            int* nf  = curr + 24;
            int  nxt = *nf;
            free(curr);
            curr = nxt;
        }
        i = i + 1;
    }
    free(buckets);
    free(tbl_raw);
}

fn Symbol_get_scope(int sym_raw) -> int {
    if (sym_raw == 0) { return -1; }
    int* sf = sym_raw + 16;
    return *sf;
}

fn Symbol_get_type(int sym_raw) -> int {
    if (sym_raw == 0) { return 0; }
    int* tf = sym_raw + 8;
    return *tf;
}
