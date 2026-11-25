# 19 — مكتبة الرسوم البيانية والإحصاء (`lib/plot.mg`)

دليل توثيقي شامل لمكتبة الرسوم البيانية والإحصاء **Falcon Plot** (`lib/plot.mg`)، وهي مكتبة تم تصميمها لتعمل كبديل لمكتبة `matplotlib` و `scipy.stats` في بايثون، مبنية بالكامل بلغة **Magnetar** عبر محرك الرسوم `gui.mg` وتعتمد على استدعاءات النظام المباشرة (Raw Linux Syscalls) بسرعة فائقة ودقة متناهية.

---

## 1. نظرة عامة (Overview)

توفر مكتبة `plot.mg` بيئة متكاملة لعلماء البيانات والمطورين لبناء الرسوم البيانية الإحصائية والعلمية والتفاعلية بمعدل 60 إطاراً في الثانية (60 FPS)، وتتميز بالآتي:

1. **واجهة استخدام مألوفة (Matplotlib-like API)**: دوال مطابقة لبايثون مثل `plt_figure`، `plt_plot`، `plt_scatter`، `plt_bar`، `plt_hist`، `plt_pie`، `plt_show`.
2. **محرك إحصائي متكامل (`stat_*`)**: حساب المتوسط، الوسيط، الانحراف المعياري، التباين، معامل الارتباط لبيرسون (Pearson Correlation)، والانحدار الخطي البسيط (Linear Regression).
3. **تفاعل حي (Interactive Tooltips)**: عند تحريك مؤشر الفأرة فوق أي نقطة أو شريط بياني، يظهر بالون معلومات عائم (Tooltip Card) يعرض إحداثيات النقطة بدقة.
4. **تدرج ألوان Tableau 10**: باليت ألوان علمية وعصرية تدعم الوضع الداكن (Dark Theme) والوضع الفاتح (Light Theme).
5. **ملاءمة تلقائية للمحاور (Auto-scaling)**: حساب المدى الأدنى والأقصى للبيانات وتوزيع شبكة القياس وعلامات المحاور (Ticks) مع هامش جمالي تلقائي.

---

## 2. الدوال الإحصائية والتحليلية (`stat_*`)

| الدالة | الوصف الرياضي | القيمة المرجعة |
|--------|---------------|----------------|
| `stat_sum(arr, n)` | حساب مجموع العناصر $\sum x_i$ | `int` |
| `stat_mean(arr, n)` | المتوسط الحسابي (Average) $\bar{x} = \frac{\sum x_i}{n}$ | `int` |
| `stat_min(arr, n)` | القيمة الصغرى في المصفوفة | `int` |
| `stat_max(arr, n)` | القيمة العظمى في المصفوفة | `int` |
| `stat_range(arr, n)` | المدى الإحصائي ($Max - Min$) | `int` |
| `stat_variance(arr, n)` | التباين الإحصائي $s^2 = \frac{\sum (x_i - \bar{x})^2}{n - 1}$ | `int` |
| `stat_std_dev(arr, n)` | الانحراف المعياري $s = \sqrt{Variance}$ عبر خوارزمية نيوتن السريعة | `int` |
| `stat_median(arr, n)` | الوسيط الإحصائي بعد فرز البيانات | `int` |
| `stat_quantile(arr, n, p)` | المئين (Percentile) المطلوب بنسبة مئوية (مثلاً 25 للمئين الأول Q1، و 75 للمئين الثالث Q3) | `int` |
| `stat_iqr(arr, n)` | المدى بين الربيعي ($IQR = Q3 - Q1$) لكشف القيم الشاذة | `int` |
| `stat_covariance(x, y, n)` | التباين المشترك بين سلسلتين | `int` |
| `stat_correlation(x, y, n)` | معامل ارتباط بيرسون $r \times 100$ (مثلاً `95` تعني $0.95$، `-80` تعني $-0.80$) | `int` |
| `stat_linear_regression(x, y, n, &m1000, &b)` | حساب خط الانحدار الخطي $y = \frac{m}{1000}x + b$ | `void` |
| `stat_histogram(data, n, bins, edges, counts)` | تجميع البيانات الخام وتوزيعها تلقائياً على فترات الفئات وحساب التكرارات | `void` |

---

## 3. باليت الألوان والثيمات (Colors & Themes)

```magnetar
static const int PLT_BLUE    = 0x1F77B4; // أزرق كلاسيكي
static const int PLT_ORANGE  = 0xFF7F0E; // برتقالي ساطع
static const int PLT_GREEN   = 0x2CA02C; // أخضر غابات
static const int PLT_RED     = 0xD62728; // أحمر قرمزي
static const int PLT_PURPLE  = 0x9467BD; // بنفسجي ملكي
static const int PLT_CYAN    = 0x17BECF; // سماوي بحري
static const int PLT_MINT    = 0x2ECC71; // نعناعي ناعم
```

- `plt_theme(0)`: ثيم داكن فاخر وعلمي (Dark Mode).
- `plt_theme(1)`: ثيم فاتح كلاسيكي أبيض (Light Mode).

---

## 4. دوال إعداد المخطط البياني (Plot Configuration)

```magnetar
// 1. تحديد أبعاد نافذة الرسم والعنوان
plt_figure(980, 640, "عنوان النافذة الرئيسية");

// 2. العناوين والتسميات
plt_title("عنوان المخطط");
plt_xlabel("محور السينات (X-Axis)");
plt_ylabel("محور الصادات (Y-Axis)");

// 3. التحكم في الشبكة ودليل البيانات
plt_grid(1);   // 1 = تفعيل الشبكة المرجعية، 0 = إخفاء
plt_legend(1); // 1 = إظهار صندوق دليل البيانات (Legend)

// 4. تحديد حدود المحاور يدوياً (اختياري، الافتراضي تلقائي Auto-scale)
plt_xlim(0, 100);
plt_ylim(0, 500);

// 5. تقسيم النافذة إلى مخططات متعددة (Subplots)
plt_subplot(nrows, ncols, index); // index يبدأ من 1 مثل ماتلاب وبايثون

// 6. تفريغ المخطط للبدء من جديد
plt_clf();
```

---

## 5. أنواع الرسوم البيانية المتوفرة

### 1) الرسم الخطي (`plt_plot`)
يرسم خطاً سميكاً يصل بين النقاط مع علامات دائرية على كل نقطة:
```magnetar
int x[5] = {1, 2, 3, 4, 5};
int y[5] = {10, 25, 40, 55, 70};
plt_plot(x, y, 5, PLT_BLUE, "سلسلة النمو");
```

### 2) الرسم النقطي / الانتشار (`plt_scatter`)
يرسم نقاط البيانات كدوائر مع تحديد نصف القطر واللون:
```magnetar
plt_scatter(x, y, 5, 6, PLT_CYAN, "القياسات التجريبية");
```

### 3) رسم الانحدار الخطي (`plt_regression`)
يقوم بحساب معادلة الخط الأفضل مطابقة تلقائياً ورسمه فوق البيانات:
```magnetar
plt_regression(x, y, 5, PLT_GREEN, "خط الاتجاه العام");
```

### 4) الأعمدة البيانية (`plt_bar`)
يرسم أعمدة رأسية بزوايا دائرية، مع كتابة القيمة فوق كل عمود واسم الفئة تحته:
```magnetar
string categories[3] = {"أول", "ثاني", "ثالث"};
int values[3] = {120, 250, 180};
plt_bar(categories, values, 3, PLT_ORANGE, "المبيعات");
```

### 5) المدرج التكراري (`plt_hist`)
يأخذ البيانات الخام ويقوم تلقائياً بتحديد المدى وتقسيمه إلى فترات (`bins`) وحساب تردد كل فئة:
```magnetar
int raw_data[12] = {15, 18, 22, 23, 25, 29, 31, 35, 42, 45, 50, 55};
plt_hist(raw_data, 12, 4, PLT_PURPLE, "توزيع التكرار");
```

### 6) المخطط الدائري (`plt_pie`)
يرسم دائرة مقسمة إلى قطاعات نسبية ملونة، مع حساب النسب المئوية تلقائياً وجدول جانبي:
```magnetar
string items[4] = {"سيرفرات", "شبكات", "تخزين", "دعم"};
int shares[4] = {40, 25, 20, 15};
plt_pie(shares, items, 4, "توزيع ميزانية البنية التحتية");
```

### 7) المخطط المساحي (`plt_area`)
يرسم منحنى بياني مع تعبئة وتظليل المساحة الواقعة تحته حتى خط الأساس:
```magnetar
plt_area(x, y, 5, PLT_BLUE, "المساحة التراكمية");
```

### 8) مخطط التداول والشموع اليابانية (`plt_candlestick`)
مخصص للأسواق المالية والعملات الرقمية (Trading / Stocks / Crypto)، يرسم شموع التداول مع الفتائل العلوية والسفلية، باللون الأخضر للصعود 🟢 والأحمر للهبوط 🔴:
```magnetar
// أسعار الجلسات: الافتتاح، الأعلى، الأدنى، الإغلاق
int open_p[4]  = {100, 105, 102, 110};
int high_p[4]  = {108, 112, 106, 115};
int low_p[4]   = {98,  101,  99, 107};
int close_p[4] = {105, 102, 105, 114};

plt_candlestick(open_p, high_p, low_p, close_p, 4, "شموع التداول");
```

---

## 6. أمثلة كاملة قابلة للتشغيل

### مثال 1: رسم بياني علمي وتحليل إحصائي كامل (`examples/plot_demo.mg`)

```magnetar
use "plot.mg";

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

fn main() -> int {
    print_str("Starting Falcon Matplotlib-style Charting Engine...\n");

    // 1. البيانات
    int x[10]  = {1,  2,  3,  4,  5,  6,  7,  8,  9, 10};
    int y1[10] = {12, 18, 29, 35, 42, 58, 65, 78, 88, 95};
    int y2[10] = {8,  14, 20, 24, 30, 40, 48, 55, 62, 70};

    // 2. الحسابات الإحصائية
    print_str("Mean:     "); print_int(stat_mean(y1, 10));    print_str("\n");
    print_str("Median:   "); print_int(stat_median(y1, 10));  print_str("\n");
    print_str("Std Dev:  "); print_int(stat_std_dev(y1, 10)); print_str("\n");
    print_str("Corr:     "); print_int(stat_correlation(y1, y2, 10)); print_str("%\n");

    // 3. إعداد المخطط
    plt_figure(980, 640, "Falcon Plot — Scientific & Statistical Visualization");
    plt_title("Monthly Growth & Regression Analysis");
    plt_xlabel("Timeline (Months)");
    plt_ylabel("Performance Output (Units)");
    plt_grid(1);
    plt_legend(1);

    // 4. إضافة السلاسل
    plt_plot(x, y1, 10, PLT_BLUE, "Actual Growth");
    plt_scatter(x, y1, 10, 5, PLT_CYAN, "Measurements");
    plt_plot(x, y2, 10, PLT_ORANGE, "Baseline Target");
    plt_regression(x, y1, 10, PLT_GREEN, "Best-fit Trendline");

    // 5. فتح النافذة التفاعلية (مع بالون البيانات الحي عند تحريك الفأرة)
    plt_show();
    return 0;
}
```

### مثال 2: مخطط دائري لنسب الحصص السوقية (`examples/plot_pie_demo.mg`)

```magnetar
use "plot.mg";

fn main() -> int {
    string browsers[5] = {"Chrome", "Safari", "Firefox", "Edge", "Falcon"};
    int shares[5] = {62, 18, 8, 5, 7};

    plt_figure(920, 600, "Falcon Plot — Global Market Share");
    plt_pie(shares, browsers, 5, "Global Desktop Web Browser Share (%)");

    plt_show();
    return 0;
}
```

### مثال 3: أعمدة بيانية للأرباح الفصلية (`examples/plot_bar_demo.mg`)

```magnetar
use "plot.mg";

fn main() -> int {
    string quarters[4] = {"Q1-Winter", "Q2-Spring", "Q3-Summer", "Q4-Autumn"};
    int sales[4] = {450, 720, 890, 610};

    plt_figure(900, 600, "Falcon Plot — Quarterly Sales Revenue");
    plt_title("2026 Fiscal Performance by Quarter");
    plt_ylabel("Revenue (in Thousands USD)");
    plt_grid(1);

    plt_bar(quarters, sales, 4, PLT_BLUE, "Quarterly Revenue");

    plt_show();
    return 0;
}
```

---

## 7. كيفية التجميع والتشغيل

```bash
# تجميع مثال الرسوم البيانية المتكامل
./magc examples/plot_demo.mg -o /tmp/plot_demo

# تجميع مثال الأعمدة
./magc examples/plot_bar_demo.mg -o /tmp/plot_bar_demo

# تجميع مثال المخطط الدائري
./magc examples/plot_pie_demo.mg -o /tmp/plot_pie_demo

# تجميع مثال مخطط التداول والشموع اليابانية
./magc examples/plot_trading_demo.mg -o /tmp/plot_trading_demo

# تجميع مثال المدرج التكراري
./magc examples/plot_hist_demo.mg -o /tmp/plot_hist_demo

# تشغيل أي مثال
/tmp/plot_demo
```
