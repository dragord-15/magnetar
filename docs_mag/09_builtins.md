# 09 — مرجع الدوال المدمجة (Builtins)

> **TL;DR**
> - `print` و `len` وحدهما يعملان بلا تصريح؛ وبقية الدوال تحتاج `extern fn` في أعلى الملف.
> - ثلاث طبقات: `sys_*` خام برقام syscall، و `fs_*`/`net_*` مغلّفات مبسّطة، ودوال عالية المستوى ناقصة.
> - أمثلة جاهزة للتشغيل في [أمثلة عملية لأهم 10 دوال](#أمثلة-عملية-لأهم-10-دوال).
> - كل `sys_*` تفترض **Linux x86_64**، وأرقامها هي أرقام syscall مباشرة لا تجريداً.
> - أسماء الواجهات التجريبية (`audio_play`, `sql_*`, `crypto_*`, `regex_match`, …) مذكورة في [planned/mock_builtins.md](planned/mock_builtins.md) وليست وظائف عاملة.

**حالة الدعم:** ⚠️ جزئي (بعض الدوال واجهات فقط)

المترجم يوفّر مجموعة كبيرة من الدوال **المدمجة** التي تُترجم مباشرة إلى تعليمات أو syscalls،
دون الحاجة لتعريفها. هذا المرجع مقسّم حسب الفئة.

> **ملاحظة:** أسماء الدوال المدمجة محجوزة. لا تُعرّف دالة بنفس الاسم.

---

## كيف تستعمل الدوال المدمجة: تصريح `extern fn`

في v3.5 **لا توجد مكتبة مدمجة يُشار إليها تلقائياً**. الدالة `print` و `len` وحدهما
مكتوبتان داخل المترجم (special-cased)، فتكفيهما بلا أي تصريح. أمّا بقية الدوال —
حتى الرياضية مثل `sqrt`، وحتى syscall مثل `sys_open` — فتحتاج **تصريحاً صريحاً**
في أعلى الملف:

```c
extern fn sqrt(float x) -> float;
extern fn sys_open(string path, int flags, int mode) -> int;

fn main() {
    print(sqrt(16.0));   // 4.0
}
```

- التصريح يصف **الاسم ونوع المعاملات ونوع الإرجاع** فقط؛ لا جسم للدالة.
- التصريح يجب أن يسبق الاستدعاء، وأن يكون في أعلى الملف (قبل `fn main`).
- إن استعملتَ دالة مدمجة بلا تصريح، تفشل الترجمة برسالة:

  ```text
  error: Undefined symbol 'sqrt'
  [Magnetar] Code generation failed
  ```

- التصريح لا يُترجم إلى كود: المترجم يولّد **stub** جاهزاً لهذه الدالة عند رؤية
  الاسم، ثم يمرّر الوسائط بالترتيب نفسه.

> **القاعدة:** إن كان اسم الدالة يبدأ بـ `sys_` فهو syscall خام بأرقام Linux x86_64،
> وإلا فهو مغلّف مبسّط. راجع [الطبقات الثلاث](#الطبقات-الثلاث).

---

## أمثلة عملية لأهم 10 دوال

كل الأمثلة التالية **قابلة للتشغيل مباشرة** بمترجم v3.5 على Linux x86_64.

### 1) `print` — الطبع

```c
fn main() {
    print("Hello, Magnetar!");   // نص
    print("\n");
    print(42);                   // عدد صحيح
    print(" ");
    print(3.5);                  // عدد عشري
    print("\n");
    print(true);                 // قيمة منطقية
    print("\n");
}
```

الناتج:

```text
Hello, Magnetar!
42 3.5000
true
```

- `print` **لا يضيف سطراً جديداً** — أضف `"\n"` بنفسك.
- قيمة `char` تُطبع كرقم البايت؛ مثلاً `print('M')` يطبع `77`.
- عدد صحيح يطبع كما هو، و `float` يطبع الجزء الصحيح ثم نقطة ثم الكسور — راجع
  [قيود الطباعة](12_notes_and_limitations.md#2-طباعة-الأعداد-العشرية-ليست-4-منازل-دائماً).
- قيمة منطقية تطبع `true` أو `false`، أما نتيجة المقارنة `3 < 5` فترجع `1` أو `0`.

### 2) `len` — طول النص

```c
fn main() {
    print(len("Magnetar"));   // 8
    print("\n");
    print(len(""));            // 0
    print("\n");
}
```

### 3) `sqrt` — الجذر التربيعي

```c
extern fn sqrt(float x) -> float;

fn main() {
    print(sqrt(16.0));   // 4.0
    print("\n");
    print(sqrt(2.0));    // 1.4142
    print("\n");
}
```

### 4) `pow` — القوة

```c
extern fn pow(float x, float y) -> float;

fn main() {
    print(pow(2.0, 10.0));   // 1024.0
    print("\n");
    print(pow(9.0, 0.5));    // 3.0
    print("\n");
}
```

### 5) `rand_int` — عدد صحيح عشوائي

```c
extern fn rand_int() -> int;

fn main() {
    int r = rand_int() % 100;   // خُذ الباقي لتبقي القيمة في مدى 0..99
    print(r);
    print("\n");
}
```

> **مهم:** `rand_int()` في v3.5 يقرأ عدّاد المعالج (`rdtsc`) مباشرةً، فيعيد **قيمة
> كبيرة خام** لا رقماً في مدى `0..N`. استخدم `% n` أو `& mask` لتحديد المدى.

### 6) `sleep_ms` — النوم بالميلي ثانية

```c
extern fn sleep_ms(int ms) -> void;

fn main() {
    print("start\n");
    sleep_ms(250);          // ربع ثانية
    print("after 250 ms\n");
}
```

### 7–10) `sys_open` و `sys_read` و `sys_write` و `sys_close` — قراءة ملف

هذه الدوال الأربع تعمل معاً. المثال كامل:

```c
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* buf, int count) -> int;
extern fn sys_close(int fd) -> int;
extern fn print_str(string s) -> void;

fn main() {
    // 1) افتح الملف للقراءة فقط (flags=0 هي O_RDONLY في Linux)
    int fd = sys_open("data.txt", 0, 0);
    print("fd = "); print(fd); print("\n");

    // 2) اقرأ أول 16 بايت في مخزن مؤقت
    char* buf = alloc<char>(17);      // 17 لا 16: نحتاج بايت إنهاء للنص
    int n = sys_read(fd, buf, 16);
    *(buf + 16) = 0;                  // اجعل النص منتهياً

    print("read "); print(n); print(" bytes: ");
    print_str(buf);                   // print يطبع عنوان char* — استخدم print_str للمحتوى
    print("\n");

    // 3) اكتب نفس البايتات على المخرج القياسي (fd = 1)
    sys_write(1, buf, n);
    print("\n");

    // 4) أغلق الملف
    sys_close(fd);
    print("closed\n");
}
```

قبل التشغيل، أنشئ الملف:

```bash
printf 'Hello, Magnetar!\nSecond line\n' > data.txt
```

الناتج:

```text
fd = 3
read 16 bytes: Hello, Magnetar!
Hello, Magnetar!
closed
```

| الدالة | الوسائط | المعنى |
|--------|---------|--------|
| `sys_open` | `(string path, int flags, int mode)` | يفتح ملفاً ويعيد رقم الواصف (descriptor) |
| `sys_read` | `(int fd, char* buf, int count)` | يقرأ حتى `count` بايت ويعيد عدد البايتات المقروءة |
| `sys_write` | `(int fd, char* buf, int count)` | يكتب `count` بايت ويعيد عدد البايتات المكتوبة |
| `sys_close` | `(int fd)` | يغلق الواصف |

> - أرقام `flags` هي أرقام Linux مباشرة: `0` للقراءة، `1` للكتابة، `2` للقراءة
>   والكتابة، `64` للإنشاء (`O_CREAT`).
> - `print` على `char*` يطبع **العنوان** لا المحتوى؛ لطباعة مخزن بايتات استعمل
>   `print_str` بعد إنهائه بايت صفري.
> - `sys_read` قد يُعيد عدداً أقل من المطلوب، فلا تفترض أنه قرأ كل شيء.

---

## الطبقات الثلاث

كل دوال Magnetar المدمجة تنتمي إلى إحدى ثلاث طبقات، والفرق بينها يغيّر طريقة
استعمالها تماماً:

| الطبقة | مثال | المستوى | ملاحظات |
|--------|------|---------|---------|
| `sys_*` | `sys_open` | خام | أرقام syscall مباشرة — لا تحقّق، لا تغلّف، تعمل على Linux x86_64 فقط |
| `fs_*` | `fs_exists` | مغلّف | مبسّط: ينفّذ العملية فعلاً **ويطبع سطراً تشخيصياً** — لكن قيمته المعادة غير موثوقة |
| `net_*` | `net_listen` | مغلّف | مبسّط: يطبع رسالة فقط ولا ينشئ مقبساً فعلياً |

- **`sys_*`**: ذراع حقيقي منخفض المستوى. `sys_open` مثلاً يستدعي syscall رقم 2
  مباشرة. لا تتحقق من صحة المسار ولا من الأخطاء — قيمة سالبة تعني خطأ.
- **`fs_*`**: غلاف فوق `sys_*` يضيف **طباعة تشخيصية** على الشاشة. مثال:

  ```c
  extern fn fs_exists(string path) -> int;

  fn main() {
      fs_exists("data.txt");
      // [FS] Checking if path exists: 'data.txt' -> 5
  }
  ```

  > ⚠️ **القيمة المعادة لـ `fs_*` غير موثوقة في v3.5**: المعالج يفسد سجل
  > الإرجاع قبل الطباعة، فتطبع دائماً قيمة زائفة مثل `5` سواء كان الملف موجوداً
  > أم لا. إن أردت نتيجة حقيقية، استعمل `sys_access(path, 0)` التي تُعيد `0`
  > عند وجود الملف و `-2` عند غيابه.

- **`net_*` و`thread_*` و`sql_*` و`crypto_*` و`audio_play` و`regex_match`**: واجهات
  تطبع رسائل ثابتة فقط — راجع [دوال غير مضمونة](#دوال-غير-مضمونة).

---

## الإدخال/الإخراج الأساسي

| الدالة | الوصف |
|--------|-------|
| `print(x)` | تطبع قيمة (بدون سطر جديد) — تدعم int/float/bool/char/string |
| `len(s)` | طول نص |

```c
print("Hello\n");
let n = len("abc");   // 3
```

---

## الرياضيات

| الدالة | الوصف |
|--------|-------|
| `sqrt(x)` | الجذر التربيعي |
| `sin(x)` | الجيب |
| `cos(x)` | جيب التمام |
| `tan(x)` | الظل |
| `exp(x)` | الأس e^x |
| `log(x)` | اللوغاريتم |
| `pow(x, y)` | القوة x^y |
| `rand_int()` | عدد صحيح عشوائي (قيمة `rdtsc` خام — استخدم `% n`) |
| `rand_float()` | عدد عشري عشوائي (**يعيد 0.5 ثابتة** في v3.5) |

---

## الزمن والمؤقتات

| الدالة | الوصف |
|--------|-------|
| `get_timestamp()` | الطابع الزمني الحالي |
| `sleep_ms(ms)` | نوم لعدد ملي ثانية |

---

## الذاكرة

| الدالة | الوصف |
|--------|-------|
| `new T` | تخصيص عنصر من نوع T |
| `alloc<T>(n)` | تخصيص `n` عنصراً من النوع `T` — انظر [المرجع الموحّد](07_pointers_arrays_memory.md#المرجع-الموحّد-alloctn) |
| `free(ptr)` | تحرير ذاكرة |
| `sizeof(T)` | حجم نوع بالبايت |

---

## النظام والعمليات

| الدالة | الوصف |
|--------|-------|
| `exit(code)` | إنهاء البرنامج |
| `get_timestamp()` | وقت النظام |
| `sys_fork()` | إنشاء عملية فرعية |
| `sys_getpid()` | معرّف العملية |
| `sys_getuid()` | معرّف المستخدم |
| `sys_getppid()` | معرّف العملية الأب |
| `sys_execve(...)` | تنفيذ برنامج |
| `sys_wait4(...)` | انتظار عملية |
| `sys_kill(pid, sig)` | إرسال إشارة |
| `process_exec(...)` | تنفيذ أمر (واجهة: تطبع رسالة فقط) |

---

## البيئة

| الدالة | الوصف |
|--------|-------|
| `os_get_env(name)` | قراءة متغير بيئة (واجهة: تطبع رسالة فقط) |
| `os_get_platform()` | اسم المنصة (واجهة: تعيد `MagnetarOS-x86_64-Linux`) |

---

## الملفات والمجلدات (syscalls)

| الدالة | الوصف |
|--------|-------|
| `sys_open(path, flags, mode)` | فتح ملف (3 وسائط) |
| `sys_close(fd)` | إغلاق ملف |
| `sys_read(fd, buf, n)` | قراءة |
| `sys_write(fd, buf, n)` | كتابة |
| `sys_lseek(...)` | تحريك المؤشر |
| `sys_unlink(path)` | حذف ملف |
| `sys_rename(old, new)` | إعادة تسمية |
| `sys_mkdir(path, mode)` | إنشاء مجلد |
| `sys_rmdir(path)` | حذف مجلد |
| `sys_chdir(path)` | تغيير المجلد |
| `sys_getcwd(...)` | المجلد الحالي |
| `sys_stat`, `sys_lstat`, `sys_fstat` | معلومات ملف |
| `sys_getdents64(...)` | قراءة محتوى مجلد |
| `sys_access(path, mode)` | فحص صلاحية/وجود |
| `fs_exists(path)` | هل المسار موجود؟ (ينفّذ `stat` ويطبع النتيجة — **القيمة المعادة غير موثوقة**) |
| `fs_mkdir(path)` | إنشاء مجلد (ينفّذ `mkdir` ويطبع النتيجة) |
| `fs_rm(path)` | حذف (ينفّذ `unlink` ويطبع النتيجة) |

---

## الشبكات (syscalls)

| الدالة | الوصف |
|--------|-------|
| `sys_socket(...)` | إنشاء مقبس |
| `sys_bind(...)` | ربط |
| `sys_listen(...)` | استماع |
| `sys_accept(...)` | قبول اتصال |
| `sys_connect(...)` | اتصال |
| `sys_send(...)`, `sys_sendto(...)` | إرسال |
| `sys_recv(...)`, `sys_recvfrom(...)` | استقبال |
| `sys_shutdown(...)` | إغلاق اتجاه |
| `sys_setsockopt(...)` | إعدادات المقبس |
| `sys_getsockname(...)` | اسم المقبس |
| `sys_getpeername(...)` | اسم الطرف الآخر |
| `sys_socketpair(...)` | زوج مقابس |
| `net_listen(...)`, `net_accept(...)`, `net_send(...)`, `net_close(...)` | واجهة شبكة مبسّطة (تطبع رسائل فقط) |

---

## تعدد الإرسال (Multiplexing) والحلقات

| الدالة | الوصف |
|--------|-------|
| `sys_epoll_create1(...)` | إنشاء epoll |
| `sys_epoll_ctl(...)` | التحكم بـ epoll |
| `sys_epoll_wait(...)` | انتظار أحداث |
| `sys_poll(...)` | poll |
| `sys_select(...)` | select |
| `sys_ppoll(...)`, `sys_pselect6(...)` | نسخ موسّعة |
| `sys_eventfd(...)`, `sys_eventfd2(...)` | eventfd |
| `sys_timerfd_create(...)`, `sys_timerfd_settime(...)` | timerfd |
| `sys_inotify_init1(...)` | مراقبة الملفات |

---

## الأنابيب والتحكم بالمقابس

| الدالة | الوصف |
|--------|-------|
| `sys_pipe(...)` | أنبوب |
| `sys_dup(...)`, `sys_dup2(...)`, `sys_dup3(...)` | نسخ واصفات |
| `sys_fcntl(...)` | تحكم بالوصف |
| `sys_fsync(...)`, `sys_fdatasync(...)` | مزامنة |
| `sys_ftruncate(...)`, `sys_truncate(...)` | قصّ ملف |
| `sys_flock(...)` | قفل ملف |

---

## الأداء والصلاحيات

| الدالة | الوصف |
|--------|-------|
| `sys_setuid`, `sys_setgid` | تعيين معرّفات |
| `sys_setgroups`, `sys_setresuid`, `sys_setresgid` | مجموعات وصلاحيات |
| `sys_capset` | قدرات |
| `sys_setpriority`, `sys_sched_setscheduler`, `sys_sched_yield` | جدولة |
| `sys_prctl` | تحكم بالعملية |
| `sys_chroot`, `sys_pivot_root` | جذر نظام الملفات |
| `sys_uname`, `sys_sysinfo` | معلومات النظام |
| `sys_gettid`, `sys_tgkill` | خيوط |
| `sys_setrlimit`, `sys_getrlimit` | حدود الموارد |
| `sys_nanosleep`, `sys_clock_gettime` | وقت دقيق |
| `sys_getrandom` | عشوائية آمنة |
| `sys_symlink` | رابط رمزي |
| `sys_chmod`, `sys_fchmod` | صلاحيات ملف |
| `sys_chown`, `sys_fchown`, `sys_lchown` | مالك ملف |
| `sys_mknod` | عقدة جهاز |
| `sys_statvfs` | معلومات نظام ملفات |
| `sys_swapon`, `sys_swapoff` | swap |
| `sys_sigprocmask`, `sys_rt_sigaction` | إشارات |
| `sys_reboot`, `sys_sync`, `sys_sethostname`, `sys_setsid` | إدارة النظام |
| `sys_mount`, `sys_umount2` | تحميل نظام ملفات |
| `sys_ioctl`, `sys_mmap`, `sys_munmap` | تحكم منخفض المستوى |
| `sys_readlink` | قراءة رابط |

---

## فئات عالية المستوى (واجهات مبسّطة)

| الفئة | الدوال |
|-------|--------|
| الأدوات | `print_str`, `print_int`, `print_float`, `read_line` |
| الوصول لعنوان دالة | `fn_addr` |

> الفئات الأخرى في هذا الجدول (`audio_play`, `sql_*`, `crypto_*`, `regex_match`,
> `thread_*`) هي واجهات تجريبية فقط — راجع
> [planned/mock_builtins.md](planned/mock_builtins.md).

---

## دوال واجهة فقط (Mock)

الأسماء ذات السلوك التجريبي (مثل `audio_play` و`sql_*` و`crypto_*` و`regex_match`
و`net_*` و`thread_*`) **ليست وظائف عاملة**؛ نُقل جدولها الكامل ومخرجاتها الوهمية
إلى [planned/mock_builtins.md](planned/mock_builtins.md). استخدم `sys_*` ل syscall
حقيقي، و`spawn`/`async`/`await` لتزامن فعلي.

---

## ملاحظات مهمة

- معظم `sys_*` تُترجم إلى **syscall مباشر** بأرقام Linux x86_64.
- هذه الدوال تفترض بيئة **Linux**؛ على أهداف أخرى قد لا تعمل.
- `read_line()` تقرأ **سطراً واحداً** من الإدخال القياسي (fd = 0) إلى مخزن داخلي
  من 256 بايت، وتعيد مؤشراً إلى نص منتهٍ بـ `\0`. لا توجد دالة مدمجة اسمها `read`؛
  للقراءة العامة استعمل `sys_read(0, buf, n)`.

> **حاشية — حدود syscall:** كل `sys_*` تفترض **Linux x86_64**. على `arm64` و `riscv`
> قد تفشل أو تُنتج سلوكاً مختلفاً، لأن أرقام syscall تختلف بين المعماريات.
> لذلك لا تستخدم `sys_*` إلا بعد التأكد من أن الهدف هو `x86_64`.

---
**السابق:** [08_modules.md](08_modules.md) |
**التالي:** [10_cli_reference.md](10_cli_reference.md) |
**الفهرس:** [README.md](README.md)
