# 15 — مكتبة الصور `lib/image.mg`

> **TL;DR**
> - مكتبة صور مكتوبة بلغة Magnetar بالكامل، بلا libc وبلا اعتماديات خارجية.
> - تقرأ وتكتب **PNG / BMP / PPM / PGM / TGA**.
> - الصورة داخلياً **RGBA 8-bit**، وكل الدوال تتعامل مع `Image*`.
> - المنشئ والنسخ والتحويلات تُرجع صورة جديدة يجب تدميرها بـ `image_destroy`.
> - المؤثرات (`grayscale`, `invert`, ...) تعدّل الصورة **في مكانها**؛ استخدم
>   `image_clone` أولاً إذا أردت الاحتفاظ بالأصل.

## 1. الاستيراد

أضف السطر التالي في بداية ملف `.mg`:

```c
use "lib/image.mg";
```

إذا كانت المكتبة مثبّتة في مسار المكتبات القياسي، يمكن استخدام:

```c
use "image";
```

## 2. المفاهيم الأساسية

### نوع الصورة

```c
struct Image {
    int width;
    int height;
    int channels;   // دائماً 4
    int stride;     // width * 4
    char* data;     // بكسل RGBA متتالية
    int owns_data;
};
```

كل صورة تُخزَّن كـ **RGBA** بالترتيب:

```text
index = (y * width + x) * 4
data[index + 0] = R
data[index + 1] = G
data[index + 2] = B
data[index + 3] = A
```

الإحداثيات تبدأ من الزاوية **العليا اليسرى**: `(0, 0)` أول بكسل، و`x` يميناً،
و`y` لأسفل.

### البكسل المضغوط

`image_get_pixel` تُرجع القنوات الأربع مضغوطة في `int` بالشكل:

```text
(A << 24) | (R << 16) | (G << 8) | B
```

ويمكن استخراج القنوات مباشرة:

```c
int v = image_get_pixel(img, x, y);
int r = (v >> 16) & 255;
int g = (v >> 8) & 255;
int b = v & 255;
int a = (v >> 24) & 255;
```

أو باستخدام الدوال الجاهزة: `image_get_r/g/b/a`.

### ملكية الذاكرة

| الدالة | النتيجة |
|--------|---------|
| `image_new` | صورة جديدة؛ يجب `image_destroy` |
| `image_load` | صورة جديدة؛ يجب `image_destroy` |
| `image_clone` | نسخة جديدة؛ يجب `image_destroy` |
| `image_crop` / `image_resize_*` / `image_flip_*` / `image_rotate*` | صورة جديدة؛ يجب `image_destroy` |
| `image_grayscale` / `image_invert` / ... | تعديل في المكان، لا تُرجع شيئاً |
| `image_save` | لا تدمّر الصورة |

> الدوال التي تُرجع `Image*` قد تُرجع `null` عند فشل التخصيص أو عند تمرير صورة
> غير صالحة. تحقّق من النتيجة قبل الاستخدام.

## 3. البدء السريع

```c
use "lib/image.mg";

fn main() {
    Image* img = image_new(320, 200);
    if (img == null) {
        print_str("Could not create image\n");
        return;
    }

    // خلفية متدرجة
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            image_set_pixel(img, x, y, x % 256, y, (x + y) % 256, 255);
        }
    }

    // رسم
    image_fill_circle(img, 80, 100, 40, 255, 255, 255, 255);
    image_draw_rect(img, 180, 50, 100, 80, 255, 128, 0, 255);
    image_draw_line(img, 0, 199, 319, 0, 0, 0, 0, 255);

    // حفظ
    image_save(img, "quickstart.png");
    image_save_thumbnail(img, "quickstart_thumb.png", 96);

    // نسخة رمادية مع الاحتفاظ بالأصل
    Image* gray = image_clone(img);
    if (gray != null) {
        image_grayscale(gray);
        image_save(gray, "quickstart_gray.png");
        image_destroy(gray);
    }

    image_destroy(img);
}
```

الترجمة والتشغيل:

```bash
./magc quickstart.mg -o quickstart
./quickstart
```

## 4. قراءة الصور وكتابتها

### دوال التحميل والحفظ

| الدالة | الوصف |
|--------|-------|
| `image_load(path) -> Image*` | تحميل صورة واكتشاف الصيغة تلقائياً |
| `image_load_into(img, path) -> bool` | تحميل ملف داخل صورة موجودة، مع تحرير بياناتها القديمة عند النجاح |
| `image_save(img, path) -> bool` | الحفظ حسب امتداد الملف |
| `image_save_png/bmp/ppm/pgm/tga(img, path)` | حفظ بصيغة محددة |
| `image_load_png/bmp/ppm/pgm/tga(path)` | تحميل عبر نفس الكاشف التلقائي |
| `image_save_thumbnail(img, path, max_size) -> bool` | تصغير مع الحفاظ على النسبة ثم حفظ |
| `image_print_info(img)` | طباعة `العرضxالارتفاع RGBA` |

### اختيار الصيغة

`image_save` يختار الصيغة من امتداد المسار، غير حساس لحالة الأحرف:

| الامتداد | الصيغة المكتوبة |
|----------|------------------|
| `.png` | PNG RGBA 8-bit |
| `.bmp` | BMP 24-bit (تُهمَل قناة alpha) |
| `.ppm` / `.pnm` | PPM P6 ثنائي |
| `.pgm` | PGM P5 ثنائي |
| `.tga` | TGA 32-bit غير مضغوط |
| غير معروف | PNG افتراضياً |

`image_load` يكتشف PNG وBMP وPPM/PGM من ترويسة الملف، ثم يستعين بالامتداد
لـ TGA وبقية الحالات.

### تحويل صيغة

```c
Image* img = image_load("input.bmp");
if (img != null) {
    image_save(img, "output.png");
    image_save_bmp(img, "output.bmp");
    image_save_tga(img, "output.tga");
    image_destroy(img);
}
```

### إعادة استخدام صورة موجودة

```c
Image* canvas = image_new(16, 16);
if (canvas != null) {
    if (image_load_into(canvas, "photo.png")) {
        image_save(canvas, "copy.png");
    }
    image_destroy(canvas);
}
```

## 5. إنشاء الصور والوصول إلى البكسل

| الدالة | الوصف |
|--------|-------|
| `image_new(w, h) -> Image*` | صورة RGBA جديدة معبأة بالأسود المعتم |
| `image_init(img, w, h) -> bool` | تهيئة `Image` مخصّصة مسبقاً |
| `image_free_data(img)` | تحرير بيانات صورة موجودة |
| `image_destroy(img)` | تحرير البيانات والصورة نفسها |
| `image_clone(src) -> Image*` | نسخة كاملة |
| `image_is_valid(img) -> bool` | التحقق من الصلاحية |
| `image_index(img, x, y) -> int` | فهرس البايت الأول للبكسل |
| `image_get_pixel/set_pixel` | قراءة/كتابة RGBA |
| `image_get_r/g/b/a` | قراءة قناة واحدة |
| `image_set_rgb` | كتابة RGB مع alpha = 255 |
| `image_copy_pixel` | نسخ بكسل بين صورتين |
| `image_blend_pixel` | دمج RGBA فوق بكسل موجود |

### مثال: تعديل بكسلات محددة

```c
Image* img = image_load("photo.png");
if (img != null) {
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int r = image_get_r(img, x, y);
            int g = image_get_g(img, x, y);
            int b = image_get_b(img, x, y);
            image_set_pixel(img, x, y, 255 - r, 255 - g, 255 - b, 255);
        }
    }
    image_save(img, "inverted.png");
    image_destroy(img);
}
```

> `image_set_pixel` تتجاهل الإحداثيات خارج الحدود، و`image_get_pixel` تُرجع `0`
> للإحداثيات غير الصالحة.

### صورة على stack

للاستخدام المتقدم يمكن تهيئة `Image` غير مخصّصة بـ `new`:

```c
Image img;
if (image_init(&img, 64, 64)) {
    image_set_rgb(&img, 0, 0, 255, 0, 0);
    image_free_data(&img);   // لا تستخدم image_destroy مع صورة stack
}
```

## 6. الرسم والدمج

| الدالة | الوصف |
|--------|-------|
| `image_fill(img, r, g, b, a)` | ملء الصورة بلون |
| `image_clear(img)` | ملء بالأسود المعتم |
| `image_blit(dst, src, dx, dy)` | نسخ/دمج صورة فوق أخرى |
| `image_replace_color(img, old..., new..., tolerance) -> int` | استبدال لون وإرجاع عدد البكسلات المتغيرة |
| `image_draw_line(img, x0, y0, x1, y1, r, g, b, a)` | خط Bresenham |
| `image_draw_rect(img, x, y, w, h, r, g, b, a)` | إطار مستطيل |
| `image_fill_rect(img, x, y, w, h, r, g, b, a)` | مستطيل ممتلئ |
| `image_draw_circle(img, cx, cy, radius, r, g, b, a)` | محيط دائرة |
| `image_fill_circle(img, cx, cy, radius, r, g, b, a)` | دائرة ممتلئة |

كل دوال الرسم تستخدم `image_blend_pixel`، لذلك تدعم الشفافية.

```c
Image* canvas = image_new(200, 120);
if (canvas != null) {
    image_fill(canvas, 20, 30, 40, 255);
    image_draw_rect(canvas, 10, 10, 180, 100, 255, 255, 255, 255);
    image_fill_circle(canvas, 100, 60, 30, 255, 128, 0, 200);
    image_draw_line(canvas, 10, 110, 190, 10, 0, 255, 128, 255);
    image_save(canvas, "drawing.png");
    image_destroy(canvas);
}
```

### الدمج والشفافية

```c
Image* dst = image_load("background.png");
Image* src = image_load("logo.png");

if (dst != null && src != null) {
    image_blit(dst, src, 20, 20);   // البكسلات الشفافة لا تغطي الخلفية
    image_save(dst, "composed.png");
}

image_destroy(dst);
image_destroy(src);
```

## 7. القص والتحجيم والتدوير

| الدالة | الوصف |
|--------|-------|
| `image_crop(src, x, y, w, h) -> Image*` | قص منطقة |
| `image_resize_nearest(src, nw, nh) -> Image*` | تحجيم بأقرب جار |
| `image_resize_bilinear(src, nw, nh) -> Image*` | تحجيم ثنائي الخطية |
| `image_flip_horizontal(src) -> Image*` | قلب أفقي |
| `image_flip_vertical(src) -> Image*` | قلب رأسي |
| `image_rotate90/180/270(src) -> Image*` | تدوير |

```c
Image* src = image_load("photo.png");
if (src != null) {
    Image* thumb = image_resize_bilinear(src, 128, 128);
    Image* crop = image_crop(src, 10, 10, 200, 150);
    Image* flipped = image_flip_horizontal(src);
    Image* rotated = image_rotate90(src);

    if (thumb != null) { image_save(thumb, "thumb.png"); image_destroy(thumb); }
    if (crop != null) { image_save(crop, "crop.png"); image_destroy(crop); }
    if (flipped != null) { image_save(flipped, "flipped.png"); image_destroy(flipped); }
    if (rotated != null) { image_save(rotated, "rotated.png"); image_destroy(rotated); }

    image_destroy(src);
}
```

> `image_save_thumbnail(img, path, max_size)` أبسط بديل للتصغير: يحافظ على النسبة
> ويجعل الضلع الأطول مساوياً `max_size` عند الحاجة.

## 8. المؤثرات اللونية والمرشحات

كل الدوال التالية تعدّل الصورة **في مكانها**:

| الدالة | التأثير |
|--------|---------|
| `image_grayscale(img)` | تدرّج رمادي |
| `image_invert(img)` | عكس الألوان |
| `image_brightness(img, amount)` | إضافة/طرح سطوع (-255..255 عملياً) |
| `image_contrast(img, percent)` | تغيير التباين حول 128 |
| `image_threshold(img, level)` | أبيض/أسود حسب العتبة |
| `image_sepia(img)` | تأثير سيبيا |
| `image_box_blur(img, radius)` | تمويه صندوقي |

```c
Image* img = image_load("photo.png");
if (img != null) {
    image_grayscale(img);
    image_contrast(img, 130);
    image_save(img, "processed.png");
    image_destroy(img);
}
```

للاحتفاظ بالأصل:

```c
Image* copy = image_clone(img);
if (copy != null) {
    image_sepia(copy);
    image_save(copy, "sepia.png");
    image_destroy(copy);
}
```

## 9. الصيغ المدعومة

### القراءة

| الصيغة | التفاصيل |
|--------|----------|
| PNG | أنواع 0/2/3/4/6، أعماق 1/2/4/8/16-bit، Adam7، شفافية `tRNS` |
| BMP | Palette 1/4/8-bit، 16/24/32-bit، `BI_RGB` و`BI_BITFIELDS` |
| PPM | P6 ثنائي وP3 نصي |
| PGM | P5 ثنائي وP2 نصي |
| TGA | True-color/grayscale، غير مضغوط وRLE، بما فيها الأنواع المفهرسة |

### الكتابة

| الصيغة | التفاصيل |
|--------|----------|
| PNG | RGBA 8-bit، Deflate من نوع stored blocks |
| BMP | 24-bit، بدون alpha |
| PPM | P6 ثنائي |
| PGM | P5 ثنائي |
| TGA | 32-bit، غير مضغوط، أصل أعلى اليسار |

> ملفات PNG الناتجة صحيحة وقابلة للقراءة بكل الأدوات، لكنها **غير مضغوطة**
> (stored deflate)؛ لذلك قد تكون أكبر من ملفات PNG المضغوطة العادية.

## 10. أمثلة إضافية

### تحويل صيغة مع تصغير

```c
use "lib/image.mg";

fn main() {
    Image* img = image_load("input.tga");
    if (img == null) {
        print_str("Load failed\n");
        return;
    }

    if (!image_save_thumbnail(img, "thumbnail.png", 256)) {
        print_str("Thumbnail failed\n");
    }

    if (!image_save(img, "output.bmp")) {
        print_str("Save failed\n");
    }

    image_destroy(img);
}
```

### معالجة دفعة من الصور

```c
use "lib/image.mg";

fn process(string input, string output) {
    Image* img = image_load(input);
    if (img == null) {
        print_str("Skip: ");
        print_str(input);
        print_str("\n");
        return;
    }

    image_grayscale(img);
    image_brightness(img, 10);
    image_save(img, output);
    image_destroy(img);
}

fn main() {
    process("a.png", "a_processed.png");
    process("b.bmp", "b_processed.png");
    process("c.tga", "c_processed.png");
}
```

## 11. ملاحظات وحدود

- لا توجد حالياً كتابة نصوص أو خطوط، ولا قراءة/كتابة JPEG أو GIF.
- الصور المتحركة (GIF/APNG) غير مدعومة؛ المكتبة تتعامل مع صورة ثابتة واحدة فقط.
- `image_save` لا يغيّر الصورة، لكنه يعتمد على الامتداد؛ إن كان الامتداد غير معروف
  فسيُكتب PNG.
- حفظ BMP يفقد قناة alpha، وحفظ PGM يحوّل إلى رمادي.
- كل الصور تُحمّل كاملة في الذاكرة؛ تحقّق من توفر الذاكرة للصور الكبيرة.
- الدوال التي تُرجع `Image*` يجب أن تُدمّر بـ `image_destroy`، إلا إذا استُخدم
  `image_init` على صورة stack فاستخدم `image_free_data`.
- المؤثرات تعدّل الأصل. انسخ أولاً إذا كنت تحتاج النسخة الأصلية.
- الإحداثيات خارج الحدود في `image_get_pixel` تُرجع `0`، وفي `image_set_pixel`
  تُتجاهل.
- لا توجد رسائل خطأ تفصيلية من دوال الحفظ غير القيمة المنطقية `false`.

## 12. مثال جاهز في المشروع

يوجد مثال كامل قابل للترجمة في:

```text
examples/image_demo.mg
```

تشغيله:

```bash
./magc examples/image_demo.mg -o image_demo
./image_demo
```

سينتج ملفات:

```text
image_demo.png
image_demo_thumb.png
image_demo_gray.png
image_demo_flipped.png
```

وقد تم التحقق من مخرجات المكتبة مقابل Pillow لصيغ PNG/BMP/PPM/PGM/TGA، بما فيها
PNG متداخل و16-bit وديناميكي Huffman، وTGA بنوعي 24/32-bit وRLE.
