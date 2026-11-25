# 23 — خطة إنشاء بيئة سطح مكتب Magnetar (MDE)

> **الحالة:** خطة تصميم/تنفيذ — لم يبدأ التنفيذ بعد  
> **الهدف:** بناء Desktop Environment متكامل بلغة Magnetar على Linux، بأسلوب عملي يشبه GNOME من حيث التجربة (جلسة، شريط علوي/لوحة، مشغل تطبيقات، إعدادات، إشعارات، نوافذ)، مع اعتماد واقعي على قدرات اللغة الحالية.

---

## 1. الملخص التنفيذي

المشروع المقترح: **MDE — Magnetar Desktop Environment**.

الفكرة ليست إعادة كتابة GNOME حرفياً، بل بناء بيئة سطح مكتب أصلية لـ Magnetar تتكون من:

- **Display Manager / Login Greeter** (`mde-dm` + `mde-greeter`) لتسجيل الدخول واختيار الجلسة والمستخدم.
- **Display Server / Compositor** (`mde-compositor`) لإدارة العرض، الإدخال، النوافذ، وscanout.
- **Session Manager** (`mde-session`) لإدارة الجلسة، autostart، والخدمات.
- **Window Manager / Shell** لإدارة النوافذ، workspaces، task switcher، overview.
- **Panel / Top Bar** للوقت، الشبكة، الصوت، البطارية، الإشعارات، tray.
- **App Launcher + Desktop Shell** لتشغيل التطبيقات والبحث.
- **إعدادات، ملفات، طرفية، عارض صور، محرر نصوص** كتطبيقات أساسية.
- **خدمات خلفية**: إشعارات، طاقة، شبكة، صوت، صلاحيات، إعدادات مستخدم.

**القرار المعماري الحاسم:** البدء فوق Linux الموجود (KMS/DRM + input + D-Bus/مسارات النظام) بدلاً من كتابة نواة/Display stack كامل من الصفر. هذا يقلل المخاطر ويستفيد من `lib/gui.mg` والبنية الحالية.

---

## 2. ما هو موجود اليوم في Falcon/Magnetar

| الموجود | الحالة | الاستفادة |
|---|---:|---|
| `lib/gui.mg` | قوي نسبياً | رسم مباشر DRM/framebuffer، backend X11 window، widgets، نافذة/desktop shell بسيط، أحداث فأرة/لوحة مفاتيح |
| `lib/image.mg`, `lib/font` داخل gui | متاح | أيقونات، خلفيات، خطوط/نص |
| `lib/system.mg` | متاح جزئياً | ملفات، مجلدات، stat، fork/wait/process_exec، env، cwd |
| `lib/net.mg` | متاح | اتصالات TCP/UDP؛ أساس لخدمات IPC شبكية أو أدوات نظام |
| `lib/json.mg`, `lib/file.mg`, `lib/cli.mg` | جديد/متاح | إعدادات، manifests، IPC payloads، أدوات CLI |
| syscalls في backend x86_64 | جيد | socket, poll, epoll, fork/exec/wait, ioctl, mmap, dup, pipe/eventfd/timerfd جزئياً |
| `examples/gui_desktop.mg` | مثال أولي | إثبات مفهوم Desktop shell داخل نافذة واحدة |

## 3. الفجوات الحالية (يجب سدها)

| الفجوة | الأثر | الأولوية |
|---|---|---:|
| لا يوجد Wayland compositor/protocol | لا يمكن استضافة تطبيقات Wayland أصلية مثل GNOME | عالية جداً |
| لا يوجد IPC محلي عام (Unix domain socket API عالي المستوى) | صعب بناء خدمات session/notifications/settings | عالية جداً |
| `lib/system.mg` يفتقد APIs مهمة: pipe/dup2/spawn كامل/kill/signals/readdir غني/permissions | إدارة عمليات وخدمات ضعيفة | عالية |
| لا يوجد input stack كامل (libinput/evdev abstraction، hotplug) | لوحة مفاتيح/فأرة/تاتش باد متعدد الأجهزة محدود | عالية |
| لا يوجد إدارة جلسة/تسجيل دخول/seat | لا توجد جلسة مستخدم حقيقية | عالية |
| لا يوجد sound/power/network integration | Panel غير مكتمل | متوسطة |
| `lib/gui.mg` مدير نوافذ داخلي فقط، ليس compositor نظام | لا يعزل تطبيقات متعددة العمليات جيداً | عالية |
| الخطوط/النصوص محدودة (bitmap/font بسيط) | UI احترافي محدود، لغات/Unicode محدود | متوسطة |
| لا يوجد accessibility/theming engine متقدم | تجربة GNOME-like ناقصة | متوسطة |

---

## 4. المبادئ المعمارية

1. **عملية لكل مكون حساس**: compositor، panel، launcher، settings daemon عمليات منفصلة.
2. **IPC واضح وصغير**: Unix domain sockets + JSON-RPC/line-delimited JSON كبداية.
3. **كل شيء قابل للاستبدال**: الواجهة بين shell وcompositor عبر بروتوكول داخلي موثق.
4. **MVP أولاً**: نافذة واحدة/جلسة بسيطة تعمل قبل دعم Wayland كامل.
5. **لا نكسر الموجود**: البناء فوق `lib/gui.mg` و`lib/system.mg`؛ توسيع المكتبات بدل استبدالها.
6. **أمان افتراضي**: عدم تشغيل أوامر privileged من UI بدون تأكيد/سياسة.

---

## 5. المعمارية المقترحة

```text
+--------------------------------------------------------------------------------------+
|                                  Boot / systemd / tty                                 |
|                                          │                                            |
|                                          ▼                                            |
|                                   mde-display-manager                                 |
|                                          │                                            |
|                                          ▼                                            |
|                                      mde-greeter                                      |
|                                 (user/password/session)                               |
|                                          │ auth + session start                       |
|                                          ▼                                            |
|                                 Magnetar Desktop Session                              |
|                                                                                       |
|  mde-session  ──spawn/supervise──>  mde-compositor                                   |
|      │                               │                                                |
|      │                               ├── mde-shell (background/overview/workspaces)   |
|      │                               ├── mde-panel                                   |
|      │                               ├── mde-launcher                                 |
|      │                               ├── mde-notifyd                                  |
|      │                               ├── mde-settingsd                                |
|      │                               ├── mde-polkit-agent (لاحقاً)                    |
|      │                               └── user apps (.mg / ELF)                        |
|      │                                                                                |
|      └── IPC bus (Unix sockets, /run/user/<uid>/mde/*.sock)                          |
+--------------------------------------------------------------------------------------+
                   │                    │                    │
                   ▼                    ▼                    ▼
            DRM/KMS + evdev        system services        app manifests
           /dev/dri, /dev/input    network/power/audio     ~/.local/share/mde/apps
```

### المكونات الأساسية

| المكون | المسؤولية | التقنية المقترحة |
|---|---|---|
| `mde-display-manager` | تشغيل greeter، إدارة TTY/seat، بدء جلسة المستخدم | system service + PAM/logind integration لاحقاً |
| `mde-greeter` | شاشة تسجيل دخول واختيار جلسة | Magnetar GUI fullscreen |
| `mde-session` | boot session, env, autostart, restart services | Magnetar CLI/service |
| `mde-compositor` | scanout, input, surfaces, windows, workspaces | DRM/KMS + evdev + `lib/gui.mg` drawing primitives |
| `mde-shell` | desktop background, overview, window chrome policy | جزء من compositor أو عملية shell |
| `mde-panel` | top bar, clock, tray, indicators | عملية GUI منفصلة |
| `mde-launcher` | app grid/search/run | عملية GUI منفصلة |
| `mde-notifyd` | notifications queue/toasts | daemon + IPC |
| `mde-settingsd` | إعدادات مستخدم، ثيم، خلفية، لغة | daemon + JSON config |
| `mde-files`, `mde-terminal`, ... | تطبيقات أساسية | تطبيقات Magnetar GUI |

---

## 6. خارطة الطريق بالمراحل

### المرحلة 0 — الأساس (2-4 أسابيع)

**الهدف:** تجهيز البنية التحتية البرمجية قبل أي Desktop حقيقي.

- [ ] إنشاء `lib/ipc.mg`: Unix domain socket client/server، framing (line JSON / length-prefixed).
- [ ] توسيع `lib/system.mg`: `pipe`, `dup2`, `spawn`, `kill`, `waitpid_nonblock`, `readdir`, `chmod`, `chown` حسب الحاجة.
- [ ] إضافة `lib/process.mg`: spawn + env + stdio redirection + reap.
- [ ] إضافة `lib/input.mg`: قراءة `/dev/input/event*`، key/mouse/touch events موحدة.
- [ ] إضافة `lib/fs.mg` أو تحسين `file.mg`: walk dir, temp files, atomic write.
- [ ] إضافة `lib/xdg.mg`: مسارات config/cache/runtime/autostart.
- [ ] توثيق بروتوكول MDE IPC v0 في `docs_mag/`.

**مخرجات قبول:**
- عملية A ترسل JSON-RPC لعملية B عبر Unix socket.
- spawn خدمة وقراءة stdout/stderr.
- قراءة أحداث لوحة مفاتيح/فأرة من evdev.

### المرحلة 0.5 — Display Manager و Login (2-4 أسابيع)

**الهدف:** تشغيل MDE كجلسة حقيقية، وليس فقط تطبيق تجريبي.

- [ ] `mde-display-manager`: خدمة تعمل على boot/TTY، تشغل greeter وتدير الجلسة.
- [ ] `mde-greeter`: شاشة دخول fullscreen (user, password, session, power actions).
- [ ] تكامل أولي مع PAM أو آلية auth Linux متوافقة (عبر helper/process bridge إن لزم).
- [ ] إعداد جلسة: `/usr/share/xsessions` ليس المطلوب؛ بل `/usr/share/wayland-sessions/mde.desktop` أو وحدة systemd/session مخصصة.
- [ ] بعد login ناجح: setuid/setgid/env/XDG_RUNTIME_DIR ثم spawn `mde-session`.

**مخرجات قبول:**
- ظهور greeter على tty1.
- تسجيل دخول مستخدم يفتح `mde-session`.
- فشل تسجيل الدخول لا يسقط الخدمة.

### المرحلة 1 — Compositor MVP (4-8 أسابيع)

**الهدف:** compositor بسيط يعرض أسطح تطبيقات Magnetar المحلية.

- [ ] `mde-compositor`: تهيئة DRM/KMS، backbuffer، present.
- [ ] Surface model: كل تطبيق عميل يرسم في shared buffer أو يرسل draw commands.
- [ ] Window management: focus, raise, move, resize, maximize, close.
- [ ] Input routing: keyboard focus + mouse hit testing.
- [ ] Background + cursor + basic damage tracking.
- [ ] بروتوكول داخلي `mde-proto-v1`:
  - `create_surface`, `commit`, `attach_buffer`, `set_title`, `close`, `focus`.

**مخرجات قبول:**
- تشغيل تطبيقين Magnetar كعمليتين مستقلتين داخل compositor.
- Alt+Tab، سحب نافذة، إغلاق، تكبير.

### المرحلة 2 — Session + Shell (3-6 أسابيع)

**الهدف:** تجربة جلسة سطح مكتب قابلة للاستخدام.

- [ ] `mde-session`: يقرأ autostart، يشغل compositor/panel/notifyd/settingsd، يعيد تشغيل عند crash.
- [ ] `mde-panel`: ساعة، قائمة تطبيقات، مؤشرات حالة، زر overview.
- [ ] `mde-launcher`: بحث/تشغيل التطبيقات من ملفات `.desktop`-like (`.mde-app.json`).
- [ ] Workspaces افتراضية (4 workspaces).
- [ ] Notifications/toasts عبر `mde-notifyd`.
- [ ] Lock screen بسيط.

**مخرجات قبول:**
- boot إلى جلسة MDE على tty.
- فتح launcher، تشغيل app، استلام إشعار، تبديل workspace.

### المرحلة 3 — تطبيقات أساسية (4-8 أسابيع)

| التطبيق | MVP |
|---|---|
| `mde-files` | تصفح ملفات، فتح، نسخ/نقل/حذف، sidebar |
| `mde-settings` | خلفية، ثيم، شاشة، صوت، شبكة، about |
| `mde-terminal` | PTY + shell، tabs لاحقاً |
| `mde-text` | محرر نص بسيط، open/save |
| `mde-image` | عرض صور عبر `lib/image.mg` |
| `mde-monitor` | CPU/RAM/processes، يعتمد sysmon |

### المرحلة 4 — تكامل النظام (مستمر)

- [ ] NetworkManager أو nmcli/dbus bridge.
- [ ] PulseAudio/PipeWire bridge للصوت.
- [ ] UPower/logind bridge للطاقة/الجلسة.
- [ ] XDG portals/adapters لاحقاً.
- [ ] Accessibility: keyboard nav, focus ring, scale, contrast.

---

## 7. هيكل المجلدات المقترح

```text
falcon/
  lib/
    ipc.mg                 # Unix socket + framing + JSON-RPC helpers
    process.mg             # spawn/wait/kill/stdio
    input.mg               # evdev abstraction
    compositor.mg          # surface/window/scene primitives
    desktop.mg             # desktop shell widgets/helpers
    theme.mg               # tokens, icons, fonts
  mde/
    README.md
    protocol/
      mde-ipc-v1.md
      mde-app-manifest.schema.json
    session/
      main.mg
      autostart.mg
    compositor/
      main.mg
      drm.mg
      scene.mg
      input.mg
      surface.mg
    panel/
      main.mg
    launcher/
      main.mg
    notifyd/
      main.mg
    settingsd/
      main.mg
    apps/
      files/main.mg
      settings/main.mg
      terminal/main.mg
      text/main.mg
      image/main.mg
  docs_mag/
    23_desktop_environment_plan.md
```

---

## 8. بروتوكول IPC المقترح (v0)

نقل عبر Unix domain socket، رسالة JSON واحدة لكل سطر.

```json
{"type":"request","id":1,"method":"window.create","params":{"title":"Files","w":800,"h":600}}
{"type":"response","id":1,"ok":true,"result":{"window_id":7}}
{"type":"event","event":"input.key","params":{"key":"A","mods":["ctrl"],"pressed":true}}
```

### القنوات

| socket | المالك | الاستخدام |
|---|---|---|
| `/run/user/$UID/mde/compositor.sock` | compositor | surfaces, input, window ops |
| `/run/user/$UID/mde/notify.sock` | notifyd | إشعارات |
| `/run/user/$UID/mde/settings.sock` | settingsd | get/set config |
| `/run/user/$UID/mde/session.sock` | session | start/stop/restart services |

---

## 9. نموذج تطبيق MDE

ملف manifest: `~/.local/share/mde/apps/files.mde.json`

```json
{
  "id": "org.magnetar.files",
  "name": "Files",
  "exec": "/usr/lib/mde/apps/mde-files",
  "icon": "/usr/share/mde/icons/files.png",
  "categories": ["System", "Utility"],
  "single_instance": false
}
```

اتفاق تشغيل:
- التطبيق يتصل بـ `MDE_COMPOSITOR_SOCK`.
- ينشئ surface/window، يرسل buffers/commands، يستقبل input events.
- يقرأ الإعدادات من `MDE_SETTINGS_SOCK`.

---

## 10. المكتبات التي يجب بناؤها أولاً

| المكتبة | الاعتماد | سبب الأولوية |
|---|---|---|
| `lib/ipc.mg` | `lib/net.mg`/sys_socket Unix + `lib/json.mg` | العمود الفقري لكل مكونات DE |
| `lib/process.mg` | `lib/system.mg`, sys_fork/exec/wait/pipe/dup2 | session manager وتطبيقات |
| `lib/input.mg` | sys_open/read/ioctl/poll | compositor/input routing |
| `lib/xdg.mg` | `lib/file.mg`, env | مسارات config/cache/runtime/autostart |
| `lib/theme.mg` | `lib/json.mg`, gui | ثيم موحد لكل shell/apps |
| `lib/compositor_protocol.mg` | `lib/ipc.mg` | فصل البروتوكول عن التنفيذ |

---

## 11. المخاطر والتخفيف

| الخطر | التأثير | التخفيف |
|---|---|---|
| Wayland compositor معقد جداً | تأخر كبير | ابدأ بـ Magnetar-native compositor protocol + X11 fallback للتطبيقات الخارجية |
| ضعف دعم الخطوط/Unicode | واجهة محدودة | MVP بbitmap font؛ خطة لاحقة لـ FreeType/HarfBuzz عبر FFI/process helper |
| إدارة عمليات/syscalls ناقصة في stdlib | session غير مستقر | بناء `lib/process.mg` و`lib/ipc.mg` في المرحلة 0 |
| أداء الرسم | بطء/tearing | damage regions، double buffer، DRM page flip لاحقاً |
| تعدد الأجهزة input | عدم عمل الفأرة/لوحة المفاتيح | abstraction evdev + hotplug عبر inotify |
| اتساع نطاق المشروع | عدم الإنهاء | MVP صارم: compositor + panel + launcher + 2 apps |

---

## 12. MVP واقعي (أول إصدار قابل للعرض)

**الاسم:** MDE 0.1 "Falcon Shell"

يشمل فقط:
1. `mde-display-manager` + `mde-greeter` بسيط (أو auto-login dev mode مع greeter placeholder).
2. `mde-session` يشغل 3 عمليات: compositor, panel, launcher.
3. `mde-compositor` fullscreen على DRM/KMS، يدعم نوافذ تطبيقات Magnetar عبر IPC.
4. `mde-panel`: ساعة + زر launcher + قائمة نوافذ + زر خروج.
5. `mde-launcher`: يعرض apps من مجلد manifests ويشغلها.
6. تطبيقان: `mde-files` بسيط و`mde-settings` (خلفية/ثيم فقط).
7. ملف إعدادات JSON: `~/.config/mde/settings.json`.

**خارج MVP:** Wayland خارجي كامل، network manager GUI كامل، audio mixer، accessibility كامل، دعم multi-seat متقدم.

---

## 13. معايير القبول

- [ ] الإقلاع من TTY إلى شاشة MDE بدون X11/GNOME.
- [ ] فتح/إغلاق/تحريك/تكبير نافذتين على الأقل.
- [ ] تبديل focus بالفأرة وAlt+Tab.
- [ ] تشغيل تطبيق من launcher عبر manifest.
- [ ] إعادة تشغيل panel تلقائياً إذا انهار (session supervisor).
- [ ] إعداد الثيم/الخلفية يُحفظ ويُحمّل بعد إعادة التشغيل.
- [ ] لا تسريب واضح للـ fds/memory في حلقة compositor لمدة 30 دقيقة.

---

## 14. أوامر التطوير المقترحة

```bash
# بناء مكتبة/أداة
./magc mde/compositor/main.mg -o build/mde-compositor
./magc mde/panel/main.mg -o build/mde-panel
./magc mde/session/main.mg -o build/mde-session

# تشغيل compositor على tty (يتطلب صلاحيات DRM/input)
./build/mde-session --config ~/.config/mde/session.json

# وضع تطوير داخل X11 (نافذة واحدة) باستخدام gui backend الحالي
DISPLAY=:0 ./build/mde-compositor --dev-x11
```

---

## 15. خطة مدير العرض (Display Manager) بالتفصيل

`mde-display-manager` هو المكون الذي يجعل MDE بيئة سطح مكتب قابلة للإقلاع، وليس مجرد تطبيق.

### مسؤولياته
- التشغيل كخدمة systemd على boot (`mde-dm.service`).
- حجز TTY مناسب (عادة tty7) وإعداد seat/session.
- تشغيل `mde-greeter` كعملية GUI معزولة.
- استقبال نتيجة المصادقة من greeter (Unix socket خاص root-only).
- إنشاء جلسة المستخدم: env (`HOME`, `USER`, `XDG_RUNTIME_DIR`, `MDE_SESSION_SOCK`)، setuid/setgid، groups.
- تشغيل `mde-session` ومراقبته؛ عند logout يعيد greeter.
- إيقاف آمن عند shutdown/reboot.

### واجهات مقترحة
```text
/run/mde/dm.sock              # greeter <-> display manager (root)
/usr/lib/mde/mde-greeter      # UI binary
/usr/lib/mde/mde-session      # session binary
/etc/mde/dm.json              # config: default session, autologin dev, tty
```

### مخاطر DM
- PAM/logind معقدان؛ MVP يمكنه استخدام helper خارجي أو dev autologin، لكن التصميم يجب أن يعزل auth خلف واجهة.

## 16. خطة مدير العرض الرسومي (Compositor) بالتفصيل

`mde-compositor` هو قلب البيئة: يملك الشاشة والإدخال ويوزع النوافذ.

### مسؤولياته
- **Modesetting/Scanout**: DRM/KMS، اختيار mode، page flip/double buffer.
- **Input**: evdev/libinput-like abstraction، keyboard/mouse/touchpad hotplug.
- **Scene graph**: background, surfaces, windows, popups, cursor, panel layer.
- **Window manager**: focus, move/resize, maximize, minimize, close, Alt+Tab, workspaces.
- **Protocol**: استقبال أوامر من العملاء عبر IPC؛ إرسال events (input, resize, close).
- **Security**: عميل لا يقرأ buffer عميل آخر؛ صلاحيات حسب socket/uid.

### نموذج النوافذ
- `surface`: buffer + damage + commit.
- `toplevel`: surface قابل للتحريك والتكبير.
- `popup`: قوائم/tooltip مرتبطة بـ parent.
- `layer`: background/bottom/top/overlay (panel, launcher, lockscreen).

### MVP compositor
- سطح كامل الشاشة + cursor + background.
- نوافذ Magnetar-native فقط عبر IPC.
- بدون Wayland clients خارجيين في أول إصدار.

### تطور لاحق
- Wayland protocol support أو XWayland bridge.
- GPU acceleration/Vulkan/OpenGL (اختياري، بعد الاستقرار).
- fractional scaling, multi-monitor.

## 17. الخطوة التالية المباشرة

ابدأ بالمرحلة 0، بالترتيب:

1. **`lib/ipc.mg`** — Unix domain socket + request/response/event JSON.
2. **`lib/process.mg`** — spawn/pipe/wait/kill.
3. **`mde/protocol/mde-ipc-v1.md`** — توثيق العقود قبل الكود.
4. **`mde/compositor/main.mg`** — skeleton يفتح DRM أو X11 dev window ويستقبل IPC.
5. **`mde/apps/hello/main.mg`** — أول عميل يثبت البروتوكول.
6. **`mde/session/main.mg`** — يشغل compositor/panel/launcher.
7. **`mde/display-manager/main.mg`** — greeter + session lifecycle.

> هذا المسار يعطي "Desktop Environment" تدريجياً: أولاً compositor+shell، ثم display manager، ثم تكامل النظام.
