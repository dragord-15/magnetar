# دليل مكتبة Falcon GUI (`lib/gui.mg`)

مرجع عملي وشامل لبناء تطبيقات واجهة رسومية احترافية بلغة **Magnetar** باستخدام `lib/gui.mg`، مع شرح كل نافذة وكل عنصر (Widget) وكل دالة عامة، وأمثلة جاهزة للنسخ والبناء.

- ملف المكتبة: `lib/gui.mg`
- طريقة الاستيراد: `use "gui.mg";`
- البناء: `./magc app.mg -o /tmp/app`
- التشغيل: `/tmp/app` (أو `DISPLAY=:0 /tmp/app`)

---

## 1. لماذا هذه المكتبة؟

- تعمل مباشرة عبر **استدعاءات نظام لينكس الخام** دون `libc` أو `libX11`.
- وضعان: **X11 نافذة سطح مكتب**، و**framebuffer/DRM مباشر** للأنظمة المدمجة.
- وضعان للتطبيقات:
  - **وضع التطبيق (App Mode)**: نافذة رئيسية واحدة تملأ كامل مساحة العميل، لها شريط عنوان ومحتوى، مثل النافذة الداخلية تماماً. يستخدم `dsk_init_window()`.
  - **وضع سطح المكتب (Desktop Shell)**: عدة نوافذ عائمة + شريط مهام Taskbar. يستخدم `dsk_init()`.
- نظام Widgets موحد: أزرار، حقول إدخال قابلة للكتابة، قوائم، تبويبات، بطاقات، Spinner، شرائح Slider، Badges، وغيرها.
- حلقة أحداث جاهزة بمعدل ~60 إطاراً في الثانية عبر `dsk_frame()`.
- أربعة ثيمات جاهزة + إمكانية تغيير لون التمييز (Accent) أثناء التشغيل.
- دعم تغيير حجم النافذة وإعادة التدفق تلقائياً (`dsk_on_resize()`).
- Toast notifications + إدخال لوحة مفاتيح + عجلة الفأرة + زر الفأرة الأيمن.

---

## 2. البداية السريعة: نافذة تطبيق واحدة

الهدف: نافذة واحدة فقط، بلا شريط عنوان مزدوج. في الوضع الافتراضي يعتمد التطبيق على شريط عنوان مدير النوافذ (OS) ولا يرسم شريطاً داخلياً إضافياً.

```magnetar
use "gui.mg";

fn main() -> int {
    // استدعاء واحد فقط: يفتح النافذة ويعيد مقبض النافذة الجذرية
    int win = dsk_open(900, 600, "My App");
    if (win < 0) { return 1; }

    dsk_set_theme(1);

    dsk_label(win, 24, 24, 400, 22, "Welcome");
    int name = dsk_input(win, 24, 60, 300, 32, "");
    int ok = dsk_button(win, 24, 108, 120, 36, "Say hi");
    int out = dsk_label(win, 24, 160, 500, 22, "");

    while (dsk_running() == 1) {
        int clicked = dsk_frame();
        if (clicked == ok) {
            dsk_widget_set_label(out, dsk_widget_text(name));
        }
    }

    dsk_shutdown();
    return 0;
}
```

### البديل: تهيئة + الحصول على النافذة
إذا أردت فحص خطأ التهيئة:

```magnetar
int err = dsk_init_window(900, 600, "My App");
if (err != 0) { return err; }
int win = dsk_root();          // لا تستدعِ dsk_add_window في وضع التطبيق
```

### نقاط مهمة
- **لا تستدعِ `dsk_add_window()` بعد `dsk_init_window()`** في وضع التطبيق. النافذة الجذرية أُنشئت تلقائياً، واستخدام `dsk_add_window` إضافي غير ضروري.
- افتراضياً `dsk_root_chrome() == 0`: شريط عنوان واحد فقط من مدير النوافذ، ومحتوى النافذة يبدأ من `y = 0`.
- إذا أردت شريط عنوان داخلياً من تصميم المكتبة (بدون شريط مدير النوافذ): استدعِ `dsk_set_root_chrome(1)`، وسيبدأ المحتوى من `dsk_content_top()` (يساوي 30).
- استخدم `dsk_open()` كأبسط واجهة: تهيئة + إرجاع المقبض في استدعاء واحد.


---

## 3. وضع سطح المكتب (نوافذ متعددة)

```magnetar
use "gui.mg";

fn main() -> int {
    int err = dsk_init();
    if (err != 0) { return err; }

    dsk_set_theme(0);

    int a = dsk_add_window("Files", 40, 40, 380, 300);
    dsk_label(a, 20, 46, 300, 20, "Files window");
    dsk_button(a, 20, 84, 120, 34, "Open");

    int b = dsk_add_window("Settings", 200, 140, 420, 320);
    dsk_label(b, 20, 46, 300, 20, "Settings window");
    dsk_switch(b, 20, 84, "Dark mode", 1);

    while (dsk_running() == 1) {
        dsk_frame();
    }

    dsk_shutdown();
    return 0;
}
```

في هذا الوضع:
- يظهر شريط مهام أسفل الشاشة مع زر `FALCON` وأزرار النوافذ.
- يمكن سحب النوافذ من شريط العنوان.
- أزرار النافذة: إغلاق (أحمر) يخفي النافذة، تصغير (أصفر) يبدّل الظهور، تكبير (أخضر) يبدّل بين ملء الشاشة وحجم افتراضي.
- في وضع التطبيق مع الشريط الداخلي (`dsk_set_root_chrome(1)`)، زر إغلاق النافذة الجذرية يوقف الحلقة (`dsk_stop`).

---

## 4. حلقة الأحداث (Event Loop)

### `dsk_frame()`
```magnetar
int dsk_frame() -> int
```
- ينفذ: `dsk_update()` + `gui_present()` + `sleep_ms(16)`.
- يعيد معرف الـ Widget الذي نُقر عليه في هذا الإطار (`-1` إن لم يوجد).
- يعيد أيضاً معرف حقل الإدخال عند الضغط على `Enter`.
- هو الأسلوب الموصى به.

### `dsk_update()`
```magnetar
int dsk_update() -> int
```
- يقرأ الفأرة ولوحة المفاتيح، يعالج الأحداث، يرسم كل شيء، ويعيد نفس قيمة النقر.
- استخدمه فقط إذا أردت التحكم يدوياً في `gui_present()` والتوقيت.

### دوال مساعدة
```magnetar
int  dsk_running()         // 1 ما دامت الحلقة مستمرة
void dsk_stop()            // إيقاف الحلقة
int  dsk_clicked_widget()  // آخر Widget نُقر
int  dsk_hovered_widget()  // Widget تحت المؤشر أو -1
int  dsk_hovered_window()  // النافذة تحت المؤشر أو -1
int  dsk_mouse_wheel()     // اتجاه العجلة: -1 أعلى، +1 أسفل، 0 لا شيء
int  dsk_frame_count()     // رقم الإطار الحالي
```

---

## 5. النوافذ: كل الدوال

```magnetar
int  dsk_add_window(string title, int x, int y, int w, int h)
void dsk_focus_window(int id)
int  dsk_active()
int  dsk_window_focused(int id)
int  dsk_window_visible(int id)
void dsk_toggle_window(int id)
void dsk_maximize_window(int id)
void dsk_window_show(int id)
void dsk_window_hide(int id)

int  dsk_window_x(int id)
int  dsk_window_y(int id)
int  dsk_window_w(int id)
int  dsk_window_h(int id)
string dsk_window_title(int id)
int  dsk_window_widget(int id)        // أول Widget في النافذة
int  dsk_window_widget_count(int id)  // عدد Widgets

void dsk_window_set_title(int id, string title)
void dsk_window_move(int id, int x, int y)
void dsk_window_resize(int id, int w, int h)
void dsk_window_center(int id)
```

### إدارة الوضع
```magnetar
int  dsk_root()          // معرف النافذة الجذرية أو -1
int  dsk_app_mode()      // 1 وضع تطبيق، 0 وضع سطح مكتب
int  dsk_root_chrome()   // 1 شريط عنوان داخلي، 0 شريط مدير النوافذ فقط
void dsk_set_root_chrome(int on)
int  dsk_content_top()   // أول y صالح لمحتوى النافذة الجذرية
void dsk_set_app_mode(int on)
void dsk_set_taskbar(int on)
int  dsk_taskbar_visible()
void dsk_on_resize()     // استدعِها بعد تغيير أبعاد الشاشة يدوياً
int  dsk_screen_w()
int  dsk_screen_h()
int  dsk_taskbar_h()
```

### التهيئة والإغلاق
```magnetar
int  dsk_open(int w, int h, string title)         // استدعاء واحد، يعيد مقبض النافذة أو -1
int  dsk_init_window(int w, int h, string title)  // وضع تطبيق + نافذة جذرية
int  dsk_init_app(int w, int h, string title)     // اسم بديل لـ dsk_init_window
int  dsk_init()                                   // وضع سطح مكتب
int  dsk_init_framebuffer()                       // framebuffer مباشر
void dsk_shutdown()
```

---

## 6. الثيمات والألوان

```magnetar
void dsk_set_theme(int theme_id)
void dsk_set_accent(int color)
int  gui_rgb(int r, int g, int b)
```

| `theme_id` | الاسم |
|-----------|--------|
| `0` | Modern Deep Blue (افتراضي) |
| `1` | Dark |
| `2` | Cyberpunk |
| `3` | Emerald |
| `4` | Light |
| أي رقم آخر | يعود للافتراضي |

مثال:
```magnetar
dsk_set_theme(4);                 // ثيم فاتح
dsk_set_accent(gui_rgb(220, 60, 90)); // لون تمييز مخصص
```

### متغيرات الثيم العامة
يمكنك قراءتها أو تعديلها مباشرة قبل الرسم:

`TH_DESKTOP`, `TH_PANEL`, `TH_BORDER`, `TH_TITLE`, `TH_TITLE_GRAD`, `TH_TITLE_FG`, `TH_TEXT`, `TH_SUBTEXT`, `TH_BTN`, `TH_BTN_HOVER`, `TH_BTN_FG`, `TH_ACCENT`, `TH_ACCENT_FG`, `TH_TASKBAR`, `TH_SHADOW`, `TH_SUCCESS`, `TH_INPUT_BG`, `TH_CARD`, `TH_DIVIDER`, `TH_WARNING`, `TH_DANGER`, `TH_INFO`, `TH_DISABLED`, `TH_FOCUS`, `TH_CARET`.

---

## 7. مرجع الـ Widgets

### 7.1 الأنواع والثوابت

| الثابت | القيمة | الوصف |
|--------|--------|--------|
| `WT_LABEL` | 1 | نص ثابت |
| `WT_BUTTON` | 2 | زر |
| `WT_CHECKBOX` | 3 | مربع اختيار |
| `WT_SLIDER` | 4 | شريحة قيمة |
| `WT_PROGRESS` | 5 | شريط تقدم |
| `WT_TEXTBOX` | 6 | صندوق نص للعرض فقط |
| `WT_LISTBOX` | 7 | قائمة عناصر |
| `WT_SWITCH` | 8 | مفتاح تشغيل/إيقاف |
| `WT_BADGE` | 9 | شارة حالة |
| `WT_SEPARATOR` | 10 | خط فاصل |
| `WT_TABS` | 11 | تبويبات |
| `WT_INPUT` | 12 | حقل نص قابل للكتابة |
| `WT_CARD` | 13 | بطاقة/لوحة |
| `WT_SPINNER` | 14 | مؤشر نشاط متحرك |

### 7.2 الدالة العامة لإضافة Widget
```magnetar
int dsk_add_widget(int win, int type, int x, int y, int w, int h,
                   string label, int val, int vmin, int vmax)
```
تعيد معرف الـ Widget أو `-1`.

الأغلب أنك ستستخدم الدوال المختصرة التالية بدلاً منها.

### 7.3 Label
```magnetar
int dsk_label(int win, int x, int y, int w, int h, string text)
```
- نص ثابت، يُقص عند حدود العرض.
- لتغييره: `dsk_widget_set_label(id, "new")` أو `dsk_widget_set_text(id, "new")`.

### 7.4 Button
```magnetar
int dsk_button(int win, int x, int y, int w, int h, string text)
```
- النقر يعيد معرفه من `dsk_frame()`.
- يتغير لونه عند التحويم والضغط.
- لا يستجيب إذا كان معطلاً عبر `dsk_widget_set_enabled(id, 0)`.

```magnetar
int b = dsk_button(win, 24, 80, 140, 36, "Save");
while (dsk_running() == 1) {
    if (dsk_frame() == b) { dsk_toast("Saved!"); }
}
```

### 7.5 Checkbox
```magnetar
int dsk_checkbox(int win, int x, int y, int w, int h, string text, int on)
```
- `on = 0/1` للحالة الابتدائية.
- النقر يبدّل الحالة ويضبط `WF_CHANGED`.
- اقرأ الحالة بـ `dsk_widget_on(id)` أو `dsk_widget_val(id)`.

```magnetar
int c = dsk_checkbox(win, 24, 80, 220, 22, "Remember me", 1);
if (dsk_widget_changed(c) == 1) {
    dsk_widget_clear_changed(c);
    if (dsk_widget_val(c) == 1) { /* ... */ }
}
```

### 7.6 Switch
```magnetar
int dsk_switch(int win, int x, int y, string text, int on)
```
- مفتاح عصري. العرض ثابت 44x22، والنص اختياري إلى يمينه.
- يعيد `WF_CHANGED` عند التبديل.

### 7.7 Slider
```magnetar
int dsk_slider(int win, int x, int y, int w, int h,
               int val, int vmin, int vmax)
```
- يعيد `WF_CHANGED` عند تغيّر القيمة (سحب أو نقر).
- `dsk_widget_set(id, value)` لتغيير القيمة برمجياً.
- `dsk_widget_set_range(id, vmin, vmax)` لتغيير المدى.

```magnetar
int vol = dsk_slider(win, 160, 80, 220, 22, 50, 0, 100);
if (dsk_widget_changed(vol) == 1) {
    dsk_widget_clear_changed(vol);
    dsk_widget_set(prog, dsk_widget_val(vol));
}
```

### 7.8 Progress
```magnetar
int dsk_progress(int win, int x, int y, int w, int h, int val, int vmax)
```
- شريط تقدم. `val` بين 0 و`vmax`.
- غيّره بـ `dsk_widget_set(id, new_val)`.

### 7.9 Textbox (عرض فقط)
```magnetar
int dsk_textbox(int win, int x, int y, int w, int h, string text)
```
- صندوق نص للعرض فقط، غير قابل للكتابة.
- يظهر الإطار والخلفية المناسبة.

### 7.10 Input (قابل للكتابة)
```magnetar
int dsk_input(int win, int x, int y, int w, int h, string text)
```
- حقل نصي حقيقي مع مؤشر كتابة (caret).
- عند النقر عليه يُركّز ويوضع المؤشر حسب الموضع.
- يدعم:
  - الكتابة (ASCII).
  - `Backspace` (8) و`Delete` (127).
  - `Enter` (10) يعيد معرف الحقل من `dsk_frame()`.
  - `Tab` / `Shift+Tab` للتنقل بين الحقول.
  - `Esc` (27) لإلغاء التركيز.
  - الأسهم يسار/يمين/Home/End لتحريك المؤشر (رموز 130..133).
- النص الأقصى `DSK_INPUT_CAP` (128 بايت).

```magnetar
int name = dsk_input(win, 24, 80, 300, 32, "guest");
int enter = dsk_frame();
if (enter == name) { dsk_toast(dsk_widget_text(name)); }

string s  = dsk_widget_text(name);
int caret = dsk_widget_caret(name);
```

لتغيير النص:
```magnetar
dsk_widget_set_text(name, "oussama"); // يضع المؤشر في النهاية
dsk_widget_clear_text(name);          // تفريغ
```

> ملاحظة: `dsk_widget_set_label` على حقل Input يعيد تعيين النص أيضاً (لأنها تعتمد على نفس التخزين)، لكن الأفضل استخدام `dsk_widget_set_text`.

### 7.11 Listbox
```magnetar
int dsk_listbox(int win, int x, int y, int w, int h)
int dsk_add_list_item(int box, string text)
int dsk_list_count(int box)
string dsk_list_item(int box, int index)
int dsk_list_selected(int box)
void dsk_list_select(int box, int index)
void dsk_list_clear(int box)
```
- تعرض العناصر في صفوف بارتفاع 20px.
- تدعم التمرير بعجلة الفأرة (`dsk_mouse_wheel`).
- النقر على عنصر يحدده ويضبط `WF_CHANGED`.
- `dsk_list_selected` أو `dsk_widget_val` لمعرفة العنصر المحدد.
- السعة القصوى: `DSK_MAX_ITEMS` (128 عنصر).

```magnetar
int l = dsk_listbox(win, 24, 160, 300, 150);
dsk_add_list_item(l, "Alpha");
dsk_add_list_item(l, "Bravo");
dsk_add_list_item(l, "Charlie");

if (dsk_widget_changed(l) == 1) {
    dsk_widget_clear_changed(l);
    dsk_toast(dsk_list_item(l, dsk_widget_val(l)));
}
```

### 7.12 Badge
```magnetar
int dsk_badge(int win, int x, int y, int w, int h, string text, int kind)
```
`kind`:
- `0` Info (أزرق)
- `1` Success (أخضر)
- `2` Danger (أحمر)
- `3` Warning (أصفر)

### 7.13 Separator
```magnetar
int dsk_separator(int win, int x, int y, int w)
```
خط أفقي رفيع يستخدم `TH_DIVIDER`.

### 7.14 Card
```magnetar
int dsk_card(int win, int x, int y, int w, int h)
```
- بطاقة مستطيلة بخلفية `TH_CARD` وإطار.
- ضع العناصر فوقها بإحداثيات مطلقة داخل النافذة (لا يوجد ترتيب أب/ابن تلقائي).

### 7.15 Spinner
```magnetar
int dsk_spinner(int win, int x, int y, int size)
```
- مؤشر نشاط دوّار، يتحرك تلقائياً مع كل إطار.
- `size` يُستخدم كقطر تقريبي.

### 7.16 Tabs
```magnetar
int dsk_tabs(int win, int x, int y, int w, int h,
             string labels, int active)
```
- `labels` مفصولة بـ `|` مثل: `"General|Appearance|About"`.
- `active` فهرس التبويب النشط (يبدأ من 0).
- النقر يعيد معرفه ويضبط `WF_CHANGED` ويحدّث `W_VAL` بفهرس التبويب.
- لعرض محتوى حسب التبويب اقرأ `dsk_widget_val(tabs)`.

```magnetar
int tabs = dsk_tabs(win, 24, 80, 500, 34, "One|Two|Three", 0);
if (dsk_widget_changed(tabs) == 1) {
    dsk_widget_clear_changed(tabs);
    if (dsk_widget_val(tabs) == 0) { /* One */ }
}
```

---

## 8. الدوال العامة لأي Widget

```magnetar
int    dsk_widget_type(int id)
int    dsk_widget_val(int id)
void   dsk_widget_set(int id, int val)
int    dsk_widget_on(int id)
void   dsk_widget_toggle(int id)

string dsk_widget_label(int id)
void   dsk_widget_set_label(int id, string s)
string dsk_widget_text(int id)
void   dsk_widget_set_text(int id, string s)
void   dsk_widget_clear_text(int id)
int    dsk_widget_caret(int id)

int    dsk_widget_visible(int id)
int    dsk_widget_enabled(int id)
void   dsk_widget_show(int id)
void   dsk_widget_hide(int id)
void   dsk_widget_set_enabled(int id, int on)

void   dsk_widget_move(int id, int x, int y)
void   dsk_widget_resize(int id, int w, int h)
void   dsk_widget_set_range(int id, int vmin, int vmax)

int    dsk_widget_changed(int id)
void   dsk_widget_clear_changed(int id)

void   dsk_focus_widget(int id)
int    dsk_focused_widget()
void   dsk_clear_focus()
```

### قواعد الاستخدام
- بعد قراءة `WF_CHANGED` استدعِ `dsk_widget_clear_changed(id)` وإلا سيبقى `1`.
- `dsk_widget_set_enabled(id, 0)` يعطّل النقر ويظهر العنصر باهتاً حيث يدعم الرسم ذلك.
- `dsk_widget_hide(id)` يخفيه كلياً ويمنع التقاط النقر.
- `dsk_widget_set` يقصّ القيمة تلقائياً بين `vmin` و`vmax` عند وجود مدى صالح.
- `dsk_focus_widget` يعمل فقط على `WT_INPUT`.

---

## 9. رايات الـ Widget (Flags)

| الثابت | القيمة | المعنى |
|--------|--------|--------|
| `WF_ENABLED` | 1 | قابل للتفاعل |
| `WF_HOVER` | 2 | تحت المؤشر |
| `WF_PRESSED` | 4 | مضغوط |
| `WF_CHANGED` | 8 | تغيّرت قيمته |
| `WF_FOCUS` | 16 | يملك تركيز لوحة المفاتيح |
| `WF_HIDDEN` | 32 | مخفي |

---

## 10. الرسم المباشر (Drawing Primitives)

مفيدة لرسم خلفيات أو أشكال مخصصة قبل/بعد `dsk_update`، أو داخل بطاقات.

```magnetar
void gui_clear(int color)
void gui_present()
void gui_put_pixel(int x, int y, int color)
void gui_fill_rect(int x, int y, int w, int h, int color)
void gui_draw_rect(int x, int y, int w, int h, int color)
void gui_fill_gradient_v(int x, int y, int w, int h, int top, int bottom)
void gui_fill_gradient_h(int x, int y, int w, int h, int left, int right)
void gui_fill_rounded_rect(int x, int y, int w, int h, int r, int color)
void gui_draw_rounded_rect(int x, int y, int w, int h, int r, int color)
void gui_fill_circle(int cx, int cy, int r, int color)
void gui_draw_char(int x, int y, int ch, int fg, int bg, int scale)
void gui_draw_text(int x, int y, string text, int fg, int bg, int scale)
int  gui_text_width(string text, int scale)
void gui_set_scale(int s)
int  gui_get_scale()
```

مساعدات نصية عليا:
```magnetar
void dsk_text_clip(int x, int y, string text, int fg, int bg, int maxw)
void dsk_text_center(int x, int y, int w, string text, int fg, int bg)
void dsk_text_clip_fg(int x, int y, string text, int fg, int maxw)
void dsk_text_center_fg(int x, int y, int w, string text, int fg)
void dsk_text_in(int x, int y, int w, int h, string s, int fg, int bg)
void dsk_hline(int x, int y, int w, int color)
void dsk_vline(int x, int y, int h, int color)
void dsk_line(int x0, int y0, int x1, int y1, int color)
void dsk_shadow(int x, int y, int w, int h)
void dsk_msg(string s, int x, int y)
string dsk_itoa(int v)
string dsk_itoa_pad(int v, int pad)
```

### 10.1 زوايا CSS وخصائص جمالية

`gui_fill_rounded_rect` و`gui_draw_rounded_rect` الآن يدعمان أي نصف قطر (وليس 6 فقط)، مع تنعيم حواف (anti-aliasing) حقيقي عبر تغطية كل بكسل. لذلك لا تظهر أطراف بارزة أو زوايا متقطعة.

```magnetar
// تعبئة بزوايا ناعمة، radius = h/2 يعطي شكلاً كبسولة (pill)
gui_fill_rounded_rect(x, y, w, h, h / 2, color);

// إطار بسماكة 1
gui_draw_rounded_rect(x, y, w, h, radius, color);

// إطار بسماكة مخصصة
gui_draw_rounded_rect_w(x, y, w, h, radius, 2, color);

// إطار نصف شفاف (حلقة تركيز مثلاً)
gui_draw_rounded_rect_ex(x, y, w, h, radius, 2, color, 120);

// تعبئة شفافة
gui_fill_rect_alpha(x, y, w, h, color, 80);
gui_fill_rounded_rect_alpha(x, y, w, h, radius, color, 80);

// تدرج عمودي بزوايا دائرية
gui_fill_rounded_gradient_v(x, y, w, h, radius, top_color, bottom_color);

// تدرج علوي فقط (شريط عنوان)
gui_fill_top_rounded_gradient_v(x, y, w, h, radius, top_color, bottom_color);
```

### 10.2 نصوص فوق تدرجات

استخدم نسخ `_fg` لرسم النص دون مسح خلفيته (مهم فوق التدرجات):

```magnetar
dsk_text_clip_fg(x, y, "Title", TH_TITLE_FG, maxw);
dsk_text_center_fg(x, y, w, "Button", fg);
gui_draw_text_fg(x, y, "Label", color, 255);
```

### 10.3 أدوات الألوان

```magnetar
int gui_mix_color(int c1, int c2, int t) // t=0 -> c1, t=255 -> c2
int gui_lighten(int color, int amount)   // تفتيح
int gui_darken(int color, int amount)    // تعتيم
```

### 10.4 الظلال والشفافية في الودجات

- الأزرار: ظل خفيف + تدرج رأسي + نص شفاف الخلفية.
- البطاقات: ظل ناعم متعدد الطبقات.
- الشرائح Switch والـ Badge: زوايا كبسولة `h / 2`.
- حقول الإدخال: حلقة تركيز (focus ring) شفافة بسماكة 2px.
- النوافذ: شريط عنوان متدرج مقصوص على الزوايا العلوية الدائرية.

كل هذه الخصائص مبنية على نفس الدوال أعلاه، ويمكنك إعادة استخدامها في عناصر مخصصة.

مثال خلفية مخصصة:
```magnetar
gui_clear(TH_DESKTOP);
gui_fill_gradient_v(0, 0, dsk_screen_w(), dsk_screen_h(),
                    gui_rgb(20, 30, 60), gui_rgb(8, 10, 20));
```

---

## 11. الإدخال: الفأرة ولوحة المفاتيح

### الفأرة
```magnetar
int gui_mouse_x()
int gui_mouse_y()
int gui_mouse_left()
int gui_mouse_clicked()
int gui_mouse_right()
int gui_mouse_right_clicked()
int gui_mouse_wheel()
void gui_read_mouse()
```
- العجلة تعيد `-1` للأعلى و`+1` للأسفل في الإطار الذي حدث فيه التدوير.
- `dsk_update` يقرأ الفأرة تلقائياً؛ لا تستدعِ `gui_read_mouse` يدوياً داخل حلقة `dsk_frame`.

### لوحة المفاتيح
```magnetar
int gui_key_available()
int gui_key_poll()
int gui_shift_down()
int gui_ctrl_down()
```
- `gui_key_poll` يعيد رمز ASCII أو رمزاً خاصاً، أو `-1`.
- الرموز الخاصة داخل الإدخال: `8` Backspace، `127` Delete، `10` Enter، `9` Tab، `27` Esc، `130` يسار، `131` يمين، `132` Home، `133` End.
- `dsk_update` يعالج كل هذا تلقائياً عندما يكون هناك حقل إدخال مُركّز.

---

## 12. Toast والرسائل السريعة

```magnetar
void dsk_toast(string text)
int  dsk_toast_active()
```
- يعرض إشعاراً مؤقتاً في أسفل الشاشة (أو فوق شريط المهام).
- المدة الافتراضية حوالي 2.5 ثانية (تتناقص مع الإطارات).

```magnetar
if (clicked == save_btn) { dsk_toast("Saved successfully"); }
```

---

## 13. الثوابت المهمة

```magnetar
DSK_MAX_WIDGETS = 256
DSK_MAX_WINDOWS = 16
DSK_MAX_ITEMS   = 128
DSK_INPUT_CAP   = 128

DSK_TITLE_H   = 30   // ارتفاع شريط العنوان
DSK_RADIUS    = 6    // نصف قطر الزوايا
DSK_PAD       = 12   // هامش داخلي موحد
DSK_TASKBAR_H = 44   // ارتفاع شريط المهام
```

---

## 14. وصفة تخطيط (Layout Recipe)

- في وضع التطبيق الافتراضي (`dsk_root_chrome() == 0`) ابدأ المحتوى من `y = 24` تقريباً (لا يوجد شريط داخلي).
- إذا فعّلت الشريط الداخلي `dsk_set_root_chrome(1)` ابدأ من `dsk_content_top() + 18` (أي 48 تقريباً).
- استخدم `DSK_PAD` (12) أو 24 للهوامش الجانبية.
- ارتفاع الزر المريح: 34–40.
- ارتفاع حقل الإدخال: 30–36.
- ارتفاع Label: 20–24.
- ارتفاع Listbox: 20 لكل عنصر + 8 تقريباً.
- الفاصل بين الحقول: 8–12.
- بطاقة: ضع عنوانها في الأعلى ثم عناصرك، وتذكر أن الإحداثيات مطلقة داخل النافذة.

```magnetar
int x = 24;
int y = dsk_content_top() + 18;
int w = dsk_window_w(win) - 48;

dsk_label(win, x, y, w, 22, "Section");
y = y + 32;

dsk_label(win, x, y, 120, 20, "Name");
int f1 = dsk_input(win, x + 130, y - 4, 260, 32, "");
y = y + 44;

dsk_button(win, x, y, 140, 36, "Apply");
```

---

## 15. مثال كامل شامل

راجع الملف الجاهز:
`examples/gui_showcase.mg`

يحتوي على:
- نافذة تطبيق جذرية.
- Tabs، Badge، Card، Input، Checkbox، Switch، Slider، Progress، Textbox، Spinner، Listbox.
- Toast، تبديل الثيم، ومعالجة `WF_CHANGED`.

بناء وتشغيل:
```bash
./magc examples/gui_showcase.mg -o /tmp/gui_showcase
/tmp/gui_showcase
```

---

## 16. استكشاف الأخطاء

| المشكلة | السبب المحتمل | الحل |
|---------|----------------|------|
| النافذة الرئيسية مقسومة إلى جزء كبير وشريط صغير | استخدام `dsk_init()` بدل `dsk_init_window()` | استخدم `dsk_init_window()` أو `dsk_init_app()` |
| شريط عنوان مزدوج | استدعاء `dsk_init_window` + `dsk_add_window` معاً، أو تفعيل `dsk_set_root_chrome(1)` | استخدم `dsk_open()` فقط، أو أبقِ `dsk_root_chrome() == 0` |
| عناصر المحتوى تختفي تحت شريط العنوان | استخدمت `y < DSK_TITLE_H` مع تفعيل الشريط الداخلي | ابدأ من `dsk_content_top() + 18` أو أبقي الشريط الداخلي معطلاً |
| الكتابة لا تعمل | لا يوجد حقل Input مُركّز | انقر على الحقل أو استخدم `dsk_focus_widget(id)` |
| `dsk_widget_changed` يبقى `1` دائماً | لم تُفرّغ الراية | `dsk_widget_clear_changed(id)` بعد القراءة |
| زر لا يستجيب | معطّل أو مخفي | `dsk_widget_set_enabled(id, 1)` / `dsk_widget_show(id)` |
| الإحداثيات خاطئة بعد تغيير الحجم | لم يُعاد التخطيط | استخدم إحداثيات نسبية أو استدعِ `dsk_on_resize()` عند الحاجة |
| نص طويل يتجاوز الحقل | حدود العرض | استخدم عرضاً أكبر أو قصّ النص |

---

## 17. فهرس سريع للدوال

### التهيئة
`dsk_open`, `dsk_init`, `dsk_init_window`, `dsk_init_app`, `dsk_init_framebuffer`, `dsk_shutdown`, `dsk_running`, `dsk_stop`.

### النوافذ
`dsk_add_window`, `dsk_focus_window`, `dsk_active`, `dsk_window_focused`, `dsk_window_visible`, `dsk_toggle_window`, `dsk_maximize_window`, `dsk_window_show`, `dsk_window_hide`, `dsk_window_x/y/w/h`, `dsk_window_title`, `dsk_window_set_title`, `dsk_window_move`, `dsk_window_resize`, `dsk_window_center`, `dsk_window_widget`, `dsk_window_widget_count`.

### الوضع والشاشة
`dsk_root`, `dsk_app_mode`, `dsk_root_chrome`, `dsk_set_root_chrome`, `dsk_content_top`, `dsk_set_app_mode`, `dsk_set_taskbar`, `dsk_taskbar_visible`, `dsk_taskbar_h`, `dsk_on_resize`, `dsk_screen_w`, `dsk_screen_h`.

### الثيمات
`dsk_set_theme`, `dsk_set_accent`, `gui_rgb`.

### البنّاؤون
`dsk_label`, `dsk_button`, `dsk_checkbox`, `dsk_switch`, `dsk_slider`, `dsk_progress`, `dsk_textbox`, `dsk_input`, `dsk_listbox`, `dsk_badge`, `dsk_separator`, `dsk_card`, `dsk_spinner`, `dsk_tabs`.

### القوائم
`dsk_add_list_item`, `dsk_list_count`, `dsk_list_item`, `dsk_list_selected`, `dsk_list_select`, `dsk_list_clear`.

### Widgets عامة
`dsk_widget_type/val/set/on/toggle/label/set_label/text/set_text/clear_text/caret`, `dsk_widget_visible/enabled/show/hide/set_enabled`, `dsk_widget_move/resize/set_range`, `dsk_widget_changed/clear_changed`, `dsk_focus_widget/focused_widget/clear_focus`.

### الحلقة
`dsk_frame`, `dsk_update`, `dsk_clicked_widget`, `dsk_hovered_widget`, `dsk_hovered_window`, `dsk_mouse_wheel`, `dsk_frame_count`.

### الإدخال والرسم
`gui_mouse_*`, `gui_key_*`, `gui_shift_down`, `gui_ctrl_down`, `gui_fill_*`, `gui_draw_*`, `gui_text_width`, `dsk_text_clip`, `dsk_text_center`, `dsk_line`, `dsk_toast`.
