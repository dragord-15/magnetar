# دوال مدمجة تجريبية (Mock Builtins) — مخططة للتنفيذ الحقيقي

> هذا الفصل **ليس** مرجعاً لوظائف تعمل. هذه الأسماء مقبولة من المترجم لأسباب
> توافقية، لكنها على كلا الهدفين (`x86_64` و `arm64`) تُطبع رسالة ثابتة
> وتُعيد قيمة وهمية. نُقلت من `09_builtins.md` حتى لا توهم أحداً بالعمل.

| الدالة | ما تفعله فعلياً | القيمة المعادة |
|--------|-----------------|----------------|
| `audio_play(path)` | تطبع `[Audio] Playing track: '...'` | لا شيء |
| `sql_connect(url)` | تطبع `[SQL] Connecting to database: '...'` | `42` (وهمية) |
| `sql_query(db, q)` | تطبع `[SQL] Executing query ...` | نص `SQL Result Set Mock` |
| `crypto_hash_sha256(data)` | تطبع `[Crypto] Computing SHA-256 hash ...` | هاش ثابت مطبوع |
| `crypto_aes_encrypt(data, key)` | تطبع `[Crypto] Encrypting data: ...` | `EncryptedMockDataBlob` |
| `regex_match(pattern, text)` | تطبع `[Regex] Matching pattern: ...` | `1` دائماً |
| `process_exec(cmd)` | تطبع `[Process] Executing system command: ...` | `0` |
| `os_get_env(name)` | تطبع `[OS] Reading environment variable: ...` | `MagnetarEnvValue` |
| `os_get_platform()` | تطبع اسم المنصة | `MagnetarOS-...` |
| `thread_spawn(fn)` | تطبع `[Thread] Spawning new concurrent thread ...` | `1001` |
| `thread_join(id)` | تطبع `[Thread] Waiting for thread ID: ...` | — |
| `lock()` / `unlock()` | تطبع `[Thread] Mutex locked/unlocked successfully.` | — |
| `net_listen` / `net_accept` / `net_send` / `net_close` | تطبع `[Net] ...` | — |

## ما يعمل بدلاً منها

- للملفات والعمليات والشبكات استخدم `sys_*` مباشرة (syscalls حقيقية).
- للتزامن الحقيقي استخدم `spawn` / `async` / `await` (عمليات `clone` فعلية على Linux).
- للتشفير أو قاعدة بيانات أو صوت حقيقي: لا يوجد بديل مدمج بعد؛ استخدم syscall
  أو اكتب التنفيذ بلغة Magnetar نفسها.

> لا تعتمد على هذه الأسماء في الإنتاج حتى يُنفَّذ كل واحد منها ويُنقل إلى
> [09_builtins.md](../09_builtins.md).
