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
./magc program.mg [-c] [-o output] [--target x86_64|arm64|riscv]
./mag obj1.o obj2.o -o program [--target x86_64]
```

الهدف الافتراضي هو `x86_64`. دعماً جزئياً فقط لـ `arm64` و `riscv`.

## 3. الاختبارات / Tests

```bash
./tests/run.sh
```

تتحقق المجموعة الحالية من النطاقات، المصفوفات، المحارف، الحلقات، القسمة على صفر،
ودوال الخوارزميات وجداول التجزئة.

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
