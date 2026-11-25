# Magnetar GUI Module (`lib/gui.mg`)

> **مرجع حديث ومحدث:** راجع [`gui_reference.md`](gui_reference.md) للتوثيق الكامل الجديد (وضع التطبيق بنافذة جذرية، كل الودجات، لوحة المفاتيح، الثيمات، وأمثلة جاهزة). هذا الملف يبقى للتفاصيل التاريخية للمعمارية والرسم.

دليل توثيقي شامل واحترافي لمكتبة الواجهات الرسومية **Magnetar GUI** (`lib/gui.mg`)، وكيفية بناء تطبيقات سطح المكتب التفاعلية الحديثة (على غرار Tkinter / GTK / Qt) بدقة عرض عالية، سرعة فائقة (60 FPS)، دعم كامل لتكبير الشاشة وتغيير الأبعاد (Fullscreen / Dynamic Resizing)، مع الاحتفاظ بقدرة الرسم المباشر على الشاشة العتادية (`/dev/dri/card0` و `/dev/fb0`).

---

## 1. نظرة عامة والمعمارية (Overview & Architecture)

تعمل مكتبة `gui.mg` بالكامل عبر **استدعاءات النظام المباشرة (Raw Linux Syscalls)** دون الاعتماد على مكتبة C المعيارية (`libc`) ودون الحاجة لأي مكتبات ربط خارجية مثل `libX11` أو `xcb` أو `cairo`.

### معمارية الوضع المزدوج (Dual-Mode Architecture):

| الوضع | آلية العمل | الاستخدام والمميزات |
|-------|------------|---------------------|
| **نافذة سطح المكتب (Desktop Window Mode)** | يتصل بمقبس يونكس `/tmp/.X11-unix/X0` عبر بروتوكول X11 Wire Protocol ويقرأ مفتاح الأمان `MIT-MAGIC-COOKIE-1` مباشرة من الذاكرة والبيئة. | لتطبيقات سطح المكتب العادية (مثل Tkinter) التي تفتح نافذة تفاعلية داخل أنظمة لينكس المختلفة (Ubuntu, Fedora, Arch, GNOME, KDE, XFCE...). |
| **العتاد المباشر (Direct card0 / DRM Mode)** | يتصل ببطاقة العرض العتادية `/dev/dri/card0` عبر بروتوكول DRM/KMS Dumb Buffers مع تراجع تلقائي إلى `/dev/fb0`. | للأنظمة المدمجة (Embedded Systems)، أنظمة التشغيل المستقلة، أو وضع الطرفية الشاملة (TTY Fullscreen) بدون أي خادم نوافذ. |

---

## 2. حل مشكلة تشوه الشاشة الكاملة (Fullscreen & Resizing Solution)

### سبب المشكلة سابقاً:
عند تكبير النافذة أو تفعيل وضع الشاشة الكاملة (Fullscreen / Maximize)، كان مدير النوافذ يغير أبعاد العرض بينما يظل الـ Backbuffer محجوزاً بحجم البداية الثابت ومقيداً بسعة صغيرة، مما يؤدي إلى عدم تطابق خطوط المسح العرضية (Scanline Stride / Pitch Mismatch) وظهور خطوط مائلة مشوهة بالكامل وانهيار في الذاكرة.

### الحل الجذري المنفذ:
1. **ذاكرة احتياطية ديناميكية بسعة 4K مسبقة (`G_FB_CAPACITY`)**: تبدأ بسعة تكفي شاشات فائقة الدقة (حتى 3840x2160x4 بايت) مع إعادة تخصيص تلقائي عبر `sys_mmap` بهامش أمان (Headroom) لمنع استدعاءات النظام المتكررة أثناء سحب النافذة.
2. **معالجة فورية لحدث تغيير الأبعاد (`X11_EV_CONFIGURE`)**: يقوم المعالج `_x11_handle_resize` بتحديث:
   - أبعاد النافذة: `G_X11_WIN_W` و `G_X11_WIN_H`
   - أبعاد محرك الرسم: `G_XRES` و `G_YRES` و `G_FB_WIDTH` و `G_FB_HEIGHT`
   - حجم البايتات الحقيقي: `G_FB_SIZE`
3. **إعادة رسم متزامنة فورية**: يُعاد رسم الخلفية الشبكية وشريط المهام وجميع النوافذ الداخلية فور استلام حدث الحجم، مما يقضي تماماً على أي تشوه هندسي أو ميلان في البكسلات.

---

## 3. تحسينات السرعة ودقة العرض (High FPS & Crisp Rendering)

1. **معدل تحديث 60 إطاراً في الثانية (Smooth 60 FPS)**:
   - تم ضبط زمن الانتظار في حلقة الأحداث على `sleep_ms(16)` (بدلاً من 120ms التي كانت تسبب ثقلاً ملحوظاً).
   - استخدام مصفوفة طلبات موحدة مسبقة الحجز `G_X11_REQ_BUF` لتسريع إرسال حزم `PutImage` عبر المقبس دون أي `mmap/munmap` داخل الحلقة.
2. **تسريع مسح وتعبئة الذاكرة بـ 64-bit QWORD**:
   - تمت ترقية `gui_clear` لتملأ 32 بايت (4 معالجات 64 بت) في كل تكرار، مسرعة تفريغ الشاشة بـ 8 أضعاف.
   - تمت ترقية `gui_fill_rect` لتملأ بكسلين (8 بايت) معاً، مما يمنح استجابة فورية حتى في الشاشات فائقة الاتساع.
3. **خط IBM VGA الأصلي النقي (Crisp 8x16 Font)**:
   - تم استبدال مصفوفة الخط ببيانات الخط الأصلية المستخرجة مباشرة من الخط المعتمد لنظام لينكس بدقة 3040 رمزاً ست عشرياً، مما جعل النصوص حادة وواضحة بدون أي ميل أو انعكاس.

---

## 4. العناصر والأشكال التزيينية الجديدة (Decorative Primitives)

توفر المكتبة الآن دوال رسم احترافية لإنشاء واجهات عصرية وحديثة:

### أ) المستطيلات ذات الحواف الدائرية (Rounded Rectangles)
```magnetar
// تعبئة مستطيل بزوايا دائرية
gui_fill_rounded_rect(int x, int y, int w, int h, int radius, int color);

// رسم إطار مستطيل بزوايا دائرية
gui_draw_rounded_rect(int x, int y, int w, int h, int radius, int color);
```

### ب) التدرجات اللونية (Linear Gradients)
```magnetar
// تدرج لوني رأسي ناعم (Vertical Gradient)
gui_fill_gradient_v(int x, int y, int w, int h, int color_top, int color_bottom);

// تدرج لوني أفقي ناعم (Horizontal Gradient)
gui_fill_gradient_h(int x, int y, int w, int h, int color_left, int color_right);
```

### ج) الدوائر والظلال (Circles & Shadows)
```magnetar
// رسم وتعبئة دائرة كاملة مصقولة
gui_fill_circle(int center_x, int center_y, int radius, int color);

// إضافة ظل ناعم خلف النوافذ واللوحات (Drop Shadow)
dsk_shadow(int x, int y, int w, int h);
```

---

## 5. عناصر الواجهة الحديثة (Modern Widgets)

| الرمز التعريفي | نوع العنصر | الوصف والاستخدام |
|----------------|------------|------------------|
| `WT_LABEL` | نص ثابت | عرض العناوين والتعليمات |
| `WT_BUTTON` | زر تفاعلي | أزرار دائرية الزوايا بحالة Hover وضغط متجاوبة |
| `WT_CHECKBOX` | صندوق اختيار | خيار ثنائي مع علامة صح مميزة |
| `WT_SWITCH` | مفتاح تبديل حديث (iOS/Material Switch) | مفتاح دائري أنيق للتشغيل والإيقاف بحركة انزلاقية |
| `WT_BADGE` | وسم حالة (Pill Badge) | وسم دائري أنيق لعرض الحالة (نجاح، تحذير، خطأ، تنبيه) |
| `WT_SEPARATOR` | خط فاصل أفقي | تقسيم النوافذ وتنظيم أقسام النماذج بجمالية |
| `WT_SLIDER` | شريط تمرير سحب | منزلق لتحديد القيم والنسب المئوية مع مقبض دائري |
| `WT_PROGRESS` | شريط تقدم | شريط تقدم بتدرج لوني يعرض نسب الإنجاز |
| `WT_TEXTBOX` | حقل إدخال نصي | صندوق لإدخال الأسماء والبيانات |
| `WT_LISTBOX` | قائمة عناصر قابلة للاختيار | عرض قوائم الخيارات والتحديد منها |

---

## 6. نظام الثيمات المدمجة (Theme Engine)

تأتي المكتبة بأربعة ثيمات احترافية متكاملة يمكن التبديل بينها في أي وقت بلمسة واحدة:

1. **`dsk_theme_default()` (0)**: ثيم كلاسيكي أزرق كحلي ناصع وأنيق.
2. **`dsk_theme_dark()` (1)**: ثيم داكن فاخر (Obsidian & Indigo) مريح للعين.
3. **`dsk_theme_cyberpunk()` (2)**: ثيم نيون سايبربانك مستقبلي (Cyan & Magenta).
4. **`dsk_theme_emerald()` (3)**: ثيم الزمرد الأخضر الطبيعي الهادئ.

### التبديل بين الثيمات برمجياً:
```magnetar
// التبديل المباشر بالمعرف (0 إلى 3):
dsk_set_theme(1); // تفعيل الثيم الداكن
```

---

## 7. التحكم في النوافذ (Window Controls)

تحتوي كل نافذة تلقائياً على شريط عنوان حديث بتدرج لوني مع أزرار التحكم الثلاثة:
- 🔴 **إغلاق (Close)**: إخفاء أو إغلاق النافذة.
- 🟡 **تصغير (Minimize)**: تصغير النافذة في شريط المهام.
- 🟢 **تكبير / استعادة (Maximize / Restore)**: ملء مساحة التطبيق بالكامل أو العودة للحجم القياسي عبر النقر على الدائرة الخضراء أو استدعاء:
```magnetar
dsk_maximize_window(win_id);
```

---

## 8. مثال تطبيقي متكامل ومحدث (`examples/desktop_app_demo.mg`)

```magnetar
// تطبيق متكامل يوضح جميع الميزات الحديثة
use "gui.mg";

extern fn sleep_ms(int ms) -> void;
extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

fn main() -> int {
    print_str("Starting Falcon Modern Desktop Application...\n");

    int app_w = 880;
    int app_h = 600;

    // تهيئة نافذة سطح المكتب بدقة مخصصة
    int err = dsk_init_window(app_w, app_h, "Falcon Desktop Application");
    if (err != 0) { return err; }

    // اختيار الثيم الداكن الفاخر
    dsk_theme_dark();

    // إنشاء نافذة داخلية للأدوات
    int win = dsk_add_window("Falcon Control Center", 30, 20, 820, 520);

    // عنوان رئيسي مع وسم حالة دائري (Badge)
    dsk_add_widget(win, WT_LABEL, 24, 40, 500, 26, "Falcon Desktop Application Studio", 0, 0, 0);
    int badge_status = dsk_add_widget(win, WT_BADGE, 660, 40, 130, 26, "SYSTEM ACTIVE", 1, 0, 0);

    // خط فاصل أفقي للتنظيم
    dsk_add_widget(win, WT_SEPARATOR, 24, 100, 770, 2, "", 0, 0, 0);

    // حقل إدخال
    dsk_add_widget(win, WT_LABEL, 24, 120, 140, 26, "Operator ID:", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 180, 118, 360, 30, "admin@falcon", 0, 0, 0);

    // مفاتيح تبديل حديثة (Switches)
    dsk_add_widget(win, WT_LABEL, 24, 168, 140, 26, "Fast Scanout:", 0, 0, 0);
    int sw_scanout = dsk_add_widget(win, WT_SWITCH, 180, 168, 220, 24, "DRM Fallback", 1, 0, 0);

    dsk_add_widget(win, WT_LABEL, 24, 204, 140, 26, "Full Buffer:", 0, 0, 0);
    int sw_buffer  = dsk_add_widget(win, WT_SWITCH, 180, 204, 220, 24, "Dynamic Re-mmap", 1, 0, 0);

    // شريط تمرير وشريط تقدم
    dsk_add_widget(win, WT_LABEL, 24, 285, 140, 26, "Render Quality:", 0, 0, 0);
    dsk_add_widget(win, WT_SLIDER, 180, 285, 360, 26, "", 90, 0, 100);

    dsk_add_widget(win, WT_LABEL, 24, 325, 140, 26, "Engine Load:", 0, 0, 0);
    int prog_load = dsk_add_widget(win, WT_PROGRESS, 180, 325, 360, 24, "", 45, 0, 100);

    // خط فاصل
    dsk_add_widget(win, WT_SEPARATOR, 24, 370, 770, 2, "", 0, 0, 0);

    // أزرار العمليات
    int btn_theme = dsk_add_widget(win, WT_BUTTON, 180, 395, 180, 38, "Switch Theme", 0, 0, 0);
    int btn_boost = dsk_add_widget(win, WT_BUTTON, 380, 395, 160, 38, "Boost Progress", 0, 0, 0);
    int btn_exit  = dsk_add_widget(win, WT_BUTTON, 560, 395, 120, 38, "Exit", 0, 0, 0);

    int cur_theme = 1;
    int cur_load  = 45;

    // حلقة الأحداث بمعدل 60 FPS ناعم وسريع
    while (dsk_running() == 1) {
        int clicked = dsk_update();

        // التبديل بين الثيمات عند النقر على الزر
        if (clicked == btn_theme) {
            cur_theme = cur_theme + 1;
            if (cur_theme > 3) { cur_theme = 0; }
            dsk_set_theme(cur_theme);
        }

        // زيادة شريط التقدم
        if (clicked == btn_boost) {
            cur_load = cur_load + 15;
            if (cur_load > 100) { cur_load = 10; }
            dsk_widget_set(prog_load, cur_load);
        }

        // إنهاء التطبيق
        if (clicked == btn_exit || gui_close_requested() == 1) {
            dsk_stop();
        }

        gui_present();
        sleep_ms(16); // 60 FPS
    }

    dsk_shutdown();
    return 0;
}
```

---

## 9. طريقة التجميع والتشغيل (Build & Run)

```bash
# تجميع التطبيق عبر مجمع لغة Magnetar
./magc examples/desktop_app_demo.mg -o /tmp/desktop_app_demo

# تشغيل التطبيق في بيئة سطح المكتب
/tmp/desktop_app_demo
```
