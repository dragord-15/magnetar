# دليل الاستعمال / Usage

## 1. البناء / Build

من جذر الحزمة:

```bash
make
```

الناتج:

- `./magc` — مترجم Magnetar
- `./mag` — رابط الكائنات objects

يتطلب البناء `gcc` و `make` و `libm`.

## 2. ترجمة برنامج / Compile

```bash
./magc hello.mg -o hello
./hello
```

الخيارات الأساسية:

```bash
./magc program.mg [-c] [-o output] [--target x86_64|arm64|aarch64|windows|riscv] [--format elf|pe|asm|bin]
./mag obj1.o obj2.o -o program [--target x86_64|arm64|aarch64]
```

الهدف الافتراضي هو `arm64` على أجهزة ARM و`x86_64` على غيرها. `arm64`/`aarch64` يدعمان
التوليد المباشر وربط الكائنات عبر `mag`. `riscv` مخطط له فقط، و`baremetal` غير منفّذ.
`pe` يعمل مع `x86_64` فقط؛ `asm` و`bin` يعملان مع كلا الهدفين.

## 3. الاختبارات / Tests

```bash
./tests/run.sh          # core suite on the native target
./tests/arm64_smoke.sh  # standalone ARM64 ELF
./tests/arm64_link.sh   # magc -c --target arm64 -> mag -> run
./tests/cli_formats.sh  # aliases, asm/bin, unsupported combinations
./tests/parity.sh       # compile both targets and diff stdout/exit codes
./tests/x86_no_regression.sh # x86 ELF/MAGO/PE64 bytes vs HEAD
./tests/all.sh          # all of the above
```

تتحقق المجموعة الأساسية من النطاقات، المصفوفات، المحارف، الحلقات، القسمة على صفر،
ودوال الخوارزميات وجداول التجزئة. `parity.sh` يبلغ عن SKIP للأهداف التي لا يوجد لها
مشغّل/محاكٍ على الجهاز الحالي بدل اعتبارها نجاحاً صامتاً.

## 4. أمثلة / Examples

```bash
./magc examples/gui_about.mg -o gui_about
./gui_about
```

### GUI demo بحجم 1.5 KB

```bash
./magc examples/tiny_gui_1474.mg -o tiny_gui
stat -c '%s' tiny_gui   # 1474
./tiny_gui
xwininfo -id 0xc00001
```

هذا المثال مضغوط جداً ويستخدم قيمًا خاصة ببيئة محلية:

- `XAUTHORITY` مثبّت على `/run/user/1001/.mutter-Xwaylandauth.FN25Y3`
- إزاحات ثابتة لاسم الـ cookie وبياناته داخل ملف Xauthority

للتشغيل على جهاز آخر، استخدم `lib/gui.mg` أو `examples/gui_about.mg` بدلاً منه،
أو عدّل مسار وإزاحات ملف التفويض في أعلى الملف.

## 5. قياس الحجم / Size check

```bash
stat -c '%s' tiny_gui
readelf -lW tiny_gui
```

الملف يحتوي على رأس ELF بمقدار 64 بايت وجدول برنامج Program Header واحد بمقدار 56 بايت،
لذلك يحسب `magc` حجم الكود قبل إضافة 120 بايت من رأس الملف.

## 6. حزمة النشر / Release bundle

المجلد `release/magnetar-v3.5/` جاهز للرفع إلى GitHub كما هو. لا يحتوي على ملفات
`*.o` أو الملفات التنفيذية `mag`/`magc` أو الصور المحلية.

## 7. النشر على GitHub / Publishing

```bash
cd release/magnetar-v3.5
git init
git add .
git commit -m "Magnetar v3.5 source release"
git remote add origin https://github.com/<USER>/magnetar-lang.git
git push -u origin main
```
