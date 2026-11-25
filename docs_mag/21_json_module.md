# 21 — مكتبة JSON (`lib/json.mg`)

**حالة الدعم:** ✅ مستقر (MVP نصّي)

مكتبة JSON عامة ونقية لـ Magnetar. لا تعتمد على مكتبات خارجية غير `lib/string.mg`.

## الاستيراد

```mg
use "lib/json.mg";
```

## البناء

```mg
string obj = json_object_begin();
obj = json_object_set_str(obj, "name", "falcon");
obj = json_object_set_int(obj, "port", 8080);
obj = json_object_set_bool(obj, "ok", true);
obj = json_object_end(obj); // {"name":"falcon","port":8080,"ok":true}

string arr = json_array_begin();
arr = json_array_push_int(arr, 1);
arr = json_array_push_str(arr, "hi");
arr = json_array_end(arr); // [1,"hi"]
```

## القراءة

```mg
string name = json_get_string(obj, "name", "");
int port = json_get_int(obj, "port", 0);
bool ok = json_get_bool(obj, "ok", false);
string raw = json_get_raw(obj, "port"); // "8080"
bool has = json_has_key(obj, "name");
```

## المصفوفات والتحقق

```mg
int n = json_array_count("[1,2,3]");      // 3
string v = json_array_get("[1,\"hi\"]", 1); // hi (يفك escape للسلاسل)
string r = json_array_get_raw("[1,{\"a\":1}]", 1); // {"a":1}
bool ok = json_is_valid(obj);
```

## JSON-RPC / توافق

```mg
string res = json_rpc_result(1, "{\"ok\":true}");
string err = json_rpc_error(1, -32601, "Method not found");
```

الأسماء القديمة `mgc_json_*` متوفرة كـ aliases للتوافق.
