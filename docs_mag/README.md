# توثيق لغة Magnetar (النسر) — Magñtar

**الإصدار:** v3.5

مرحباً بك في التوثيق الكامل للغة **Magnetar** (وتُعرف أيضاً بـ **Falcon** / النسر)، وهي لغة برمجة
مترجَمة (compiled) منخفضة/متوسطة المستوى، تُترجم إلى تعليمات معالج **x86_64** أصلياً وتُنتج
ملفات تنفيذية **ELF** لأنظمة Linux.

هذا المجلد يحتوي على شرح متسلسل لكل شيء عن اللغة: من البناء والتنصيب، مروراً بأساسيات
اللغة، وصولاً إلى بنية المترجم الداخلية.

---

## خريطة التوثيق

| # | الملف | الموضوع |
|---|-------|---------|
| 00 | [00_overview.md](00_overview.md) | نظرة عامة على اللغة وفلسفتها |
| 01 | [01_build_and_run.md](01_build_and_run.md) | البناء، التنصيب، والتشغيل |
| 02 | [02_basics.md](02_basics.md) | الـ Hello World، المتغيرات، الأنواع |
| 03 | [03_operators.md](03_operators.md) | العمليات الحسابية والمنطقية والبتية |
| 04 | [04_control_flow.md](04_control_flow.md) | الشروط والحلقات |
| 05 | [05_functions.md](05_functions.md) | الدوال والمعاملات والاستدعاء الذاتي |
| 06 | [06_structs_enums.md](06_structs_enums.md) | البنى والتعدادات و switch و match |
| 07 | [07_pointers_arrays_memory.md](07_pointers_arrays_memory.md) | المؤشرات والمصفوفات وإدارة الذاكرة |
| 08 | [08_modules.md](08_modules.md) | الوحدات ونظام `use` |
| 09 | [09_builtins.md](09_builtins.md) | مرجع الدوال المدمجة (print, len, ...) |
| 10 | [10_cli_reference.md](10_cli_reference.md) | مرجع سطر الأوامر والخيارات |
| 11 | [11_compiler_architecture.md](11_compiler_architecture.md) | بنية المترجم من الداخل |
| 12 | [12_notes_and_limitations.md](12_notes_and_limitations.md) | ملاحظات وقيود اللغة الحالية |
| 13 | [13_debugging.md](13_debugging.md) | التصحيح والسلوك غير المعرّف |
| 14 | [14_fille_module.md](14_fille_module.md) | مكتبة الملفات `lib/file.mg` |
| 15 | [15_image_module.md](15_image_module.md) | مكتبة الصور `lib/image.mg` |
| 16 | [16_bytes_module.md](16_bytes_module.md) | مكتبة البايتات `lib/bytes.mg` |
| 17 | [17_http_url_module.md](17_http_url_module.md) | مكتبتا HTTP و URL، HTTPS، الخادم، Telegram و Sherlock |
| 18 | [18_gui_module.md](18_gui_module.md) | مكتبة الواجهات الرسومية `lib/gui.mg` (نوافذ سطح المكتب و card0) |
| 19 | [19_plot_module.md](19_plot_module.md) | مكتبة الرسوم البيانية والإحصاء `lib/plot.mg` (Matplotlib لـ Magnetar) |
| 20 | [20_phone_control.md](20_phone_control.md) | مكتبة وتطبيق التحكم بالهاتف عبر USB وعرض شاشته `lib/adb.mg` |
| 21 | [21_json_module.md](21_json_module.md) | مكتبة JSON العامة `lib/json.mg` |
| 22 | [22_cli_rpc_node_modules.md](22_cli_rpc_node_modules.md) | مكتبات CLI / RPC / Node العامة |
| 23 | [23_desktop_environment_plan.md](23_desktop_environment_plan.md) | خطة إنشاء بيئة سطح مكتب Magnetar (MDE) مع مدير عرض وجلسة وتطبيقات |
| 24 | [24_algorithm_hashmap_modules.md](24_algorithm_hashmap_modules.md) | مكتبات الخوارزميات والبحث والترتيب وجداول Hash السريعة |
| 25 | [25_compiler_mermaid.md](25_compiler_mermaid.md) | مخطط Mermaid تفصيلي لمسار عمل مترجم Magnetar ومكوناته |
| 26 | [26_performance_diagnosis.md](26_performance_diagnosis.md) | تشخيص الأداء: سرعة الترجمة، سرعة التنفيذ، وحجم المخرجات |
| — | [planned/mock_builtins.md](planned/mock_builtins.md) | دوال واجهات تجريبية (mock) — ليست وظائف عاملة |

---

## البدء السريع

```bash
# 1) بناء المترجم (ينتج ./magc و ./mag)
make

# 2) اكتب برنامجاً
cat > hello.mg <<'EOF'
fn main() {
    print("Hello, Magnetar!\n");
}
EOF

# 3) ترجمه
./magc hello.mg -o hello

# 4) شغّله
./hello
# الناتج: Hello, Magnetar!
```

> **ملاحظة:** اسم المترجم هو `./magc` (و `./mag` للربط)، لا `magnetar`.

---

## حالة اللغة باختصار

- ✅ **x86_64 ELF مستقر** — برامج مستقلة بلا libc، تعمل على Linux 64-bit.
- ✅ **arm64/aarch64 يعمل** — ELF مستقل وربط كائنات عبر `mag --target arm64`؛ `riscv` مخطط له ويفشل فوراً.
- ✅ **asm/bin مدعومتان** — قوائم نصية أو بايتات خام على الهدفين؛ `baremetal` مرفوض صراحةً.
- ⚠️ **بعض builtins واجهات فقط** — `audio_play` و `sql_*` و `crypto_*` و `regex_match`
  تُطبع رسائل ثابتة؛ راجع [planned/mock_builtins.md](planned/mock_builtins.md).
- ⚠️ **فحص الأنواع جزئي** — يرفض الأسماء غير المعرّفة وتعارض النص مع المتغيّر العددي،
  ويحذّر من غياب `main`؛ فحص الحدود متاح اختيارياً بـ `--bounds-check` للمصفوفات `fixed`.

التفاصيل الكاملة في [12_notes_and_limitations.md](12_notes_and_limitations.md).

تشغيل اختبارات الانحدار الحالية من جذر المشروع: `./tests/run.sh`. وهي تغطي
حالات النطاقات والمصفوفات والمحارف والحلقات والقسمة على صفر.

---

## ملف بسيط جداً

```c
fn main() {
    print("Hello, Magnetar!\n");
}
```

## مبادئ عامة

- **نقطة الدخول:** كل برنامج يبدأ من `fn main()` (وبلاها يُترجَم البرنامج لكنّه لا
  ينفّذ الجمل على المستوى الأعلى).
- **التعليقات:** `//` لسطر واحد و `/* ... */` لعدة أسطر.
- **النهاية:** كل جملة تنتهي بفاصلة منقوطة `;`.
- **النوع int هو 64-بت** بعلامة.
- **الطبع:** `print()` لا يضيف سطراً جديداً — أضف `"\n"` يدوياً.
- **الدوال المدمجة:** `print` و `len` تعملان بلا تصريح؛ وبقية الدوال تحتاج `extern fn`.

---

## لو واجهتَ خطأ

- رسالة ترجمة؟ اقرأها: في [13_debugging.md](13_debugging.md) جدول أشهر 6 رسائل خطأ
  وطريقة حلّها، وفي [10_cli_reference.md](10_cli_reference.md) نص رسائل الأخطاء كما
  يطبعها المترجم حرفياً.
- انهيار (`Segmentation fault` أو كود خروج `139`)؟ راجع
  [السلوك غير المعرّف](13_debugging.md#سلوك-غير-معرّف-undefined-behavior).
