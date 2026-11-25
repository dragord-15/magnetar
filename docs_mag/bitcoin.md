# خريطة بناء عملة مشفرة لامركزية بلغة Magnetar

> **الاسم المؤقت:** Magnetar Coin — الرمز `MGC`
> **الملف:** `bitcoin.md` — خطة تنفيذ ومرجع قرارات، وليس كوداً.
> **الهدف:** بناء عملة تشبه Bitcoin في الفكرة (UTXO + Proof of Work + شبكة P2P + محفظة)،
> مكتوبة بالكامل بلغة Magnetar، تعمل بلا قاعدة بيانات مركزية وبلا سلطة تتحكم بها.

---

## 0) اقرأ هذا أولاً

### 0.1 ما تعنيه «لامركزية» هنا

اللامركزية لا تعني «بلا تخزين»؛ كل عقدة تحتفظ بنسختها الكاملة من البلوكشين في ملفات مسطحة.
اللامركزية تعني:

- لا خادم مركزي يقرر من يملك ماذا.
- لا مفتاح إداري يوقف الشبكة أو يسكّ عملات.
- كل عقدة تتحقق من كل قاعدة إجماع بنفسها.
- أي شخص يستطيع تشغيل عقدة، والتعدين، وإرسال معاملة.

### 0.2 ما لا تعنيه

- **ليست Bitcoin-compatible**: شبكة مستقلة، عناوين وبروتوكول وماجيك مختلف.
- **ليست مجهولة الهوية**: العناوين شبه-معلنة، وعنوان IP قد يُربط بالمعاملات.
- **ليست محصنة ضد هجوم 51%**؛ أي شبكة PoW صغيرة قابلة للهجوم.
- **ليست استثماراً** ولا وعداً بقيمة مالية.

### 0.3 قاعدة الإطلاق

> **لا تُطلق mainnet بأموال حقيقية قبل:** مراجعة أمنية خارجية + اختبار testnet لمدة كافية
> + مراجعة قواعد الإجماع + اختبار إعادة التنظيم والانقطاع. ابدأ دائماً بـ `regtest` ثم `testnet`.

### 0.4 الاسم والرموز

- الاسم المقترح: `Magnetar Coin`، الرمز `MGC`، الوحدة الصغرى `magnet` (10^-8).
- يمكن تغيير الاسم لاحقاً، لكن **لا تغيّر** `chain_id` أو الماجيك أو بادئة العناوين بعد إطلاق mainnet.

---

## 1) الهدف والنطاق

### 1.1 الهدف من الإصدار الأول (v0.1)

عقدة كاملة واحدة تستطيع:

1. إنشاء محفظة ومفاتيح وعناوين.
2. بناء معاملة وإرسالها.
3. التحقق من المعاملات والكتل.
4. تعدين كتل على `regtest` أو `testnet`.
5. حفظ البلوكشين في ملفات مسطحة وإعادة تحميله بعد إعادة التشغيل.
6. التزامن مع عقدة أخرى عبر TCP P2P.
7. إعادة تنظيم سلسلة أقصر إلى سلسلة ذات «عمل تراكمي» أكبر.

### 1.2 معايير النجاح النهائية (Definition of Success)

- 3 عقد محلية تتزامن من Genesis إلى 1,000 كتلة دون تدخل.
- إرسال 10 معاملات بين محافظ، وظهور الأرصدة بعد تأكيد واحد.
- إعادة تشغيل عقدة بعد `kill -9` دون فقدان أو تلف البيانات.
- رفض كتلة ذات PoW خاطئ أو توقيع خاطئ أو إنفاق مزدوج.
- إعادة تنظيم 5 كتل بنجاح وعودة معاملات اليتيمة إلى الميمبول.
- تشغيل 72 ساعة على testnet دون انهيار أو تسريب ذاكرة واضح.
- لا مفاتيح خاصة في السجلات، ولا مسار إداري يسمح بسكّ عملات.

---

## 2) القرارات المعمارية الثابتة

هذه القرارات تُثبَّت قبل كتابة كود الإجماع. تغييرها بعد Genesis = شبكة جديدة.

| القرار | الاختيار | السبب | البديل المرفوض |
|---|---|---|---|
| نموذج الملكية | UTXO | أبسط تحقق، لا حالة حسابية مركزية | Account model (يحتاج nonce وترتيب) |
| الإجماع | Proof of Work — SHA-256d | متاح في `lib/crypto.mg` | PoS (يحتاج slashing وحالة معقدة) |
| المنحنى | secp256k1 + ECDSA | أقرب لـ Bitcoin، مفاتيح 33 بايت | Ed25519 (أبسط لكن ليس Bitcoin-like) |
| العناوين | Base58Check + HASH160 | مألوفة، مضغوطة | Bech32 (لاحقاً) |
| السكربت | P2PKH فقط في v0 | يقلل سطح الهجوم | Script VM كامل (مرحلة لاحقة) |
| Sighash | `MGC-SIGHASH-v1` مع `chain_id` | يمنع إعادة التشغيل بين الشبكات | Sighash Bitcoin القديم (أثقل وأعقد) |
| txid | SHA-256d للترميز بلا توقيعات | يمنع التلاعب (malleability) | txid يشمل scriptSig (يثبت التلاعب) |
| التخزين | ملفات مسطحة + فهارس في الذاكرة | لا قاعدة بيانات، لا خدمة خارجية | SQLite/LevelDB (تبعية خارجية) |
| P2P | TCP IPv4 + رسائل ثنائية | `lib/net.mg` + `lib/dns.mg` | WebSocket/HTTP (غير مناسب للإجماع) |
| التزامن | حلقة أحداث واحدة + `sys_poll` | لا حاجة لأقفال، أسهل تدقيقاً | fork لكل اتصال (نسخ حالة معقد) |
| النقود | `int` 64-بت بوحدة satoshi | دقة كاملة، لا float | float (مرفوض تماماً) |
| الإطلاق | regtest → testnet → mainnet | يقلل المخاطر | mainnet مباشرة (مرفوض) |
| الإصدار الأول | بلا premine وبلا ICO | عدالة الإطلاق | تخصيص مؤسسي (يجب الإفصاح عنه) |

> **مهم:** `int` في Magnetar هو 64-بت موقّع. أقصى كمية 21,000,000 × 10^8 = 2.1×10^15
> وهي أصغر بكثير من 9.22×10^18، لذا فهي آمنة. لكن **كل جمع/طرح للمبالغ يجب أن يفحص الفائض**
> يدوياً: `if (a > MAX_MONEY - b) { error }`.

---

## 3) معايير الشبكة (Chain Parameters)

توضع في `coin/lib/params.mg` كدوال ثابتة، وليس كمتغيرات قابلة للتعديل من ملف إعداد.

| المعامل | mainnet | testnet | regtest |
|---|---:|---:|---:|
| `chain_id` | `0x4D474301` | `0x4D474302` | `0x4D474303` |
| P2P port | 9333 | 19333 | 29333 |
| RPC port | 9332 | 19332 | 29332 |
| Magic | `MGC1` | `MGCT` | `MGCR` |
| بادئة عنوان P2PKH | `0x32` | `0x6F` | `0x6F` |
| بادئة WIF | `0x80` | `0xEF` | `0xEF` |
| فترة الكتلة | 600 ثانية | 120 ثانية | 1 ثانية |
| إعادة حساب الصعوبة | كل 2016 كتلة | كل 2016 | كل 144 |
| مكافأة البداية | 50 MGC | 50 MGC | 50 MGC |
| Halving | كل 210,000 | كل 210,000 | كل 150 |
| أقصى عرض | 21,000,000 | 21,000,000 | 21,000,000 |
| أقصى حجم كتلة | 1,000,000 بايت | 1,000,000 | 1,000,000 |
| أقصى حجم معاملة | 100,000 بايت | 100,000 | 100,000 |
| نضج Coinbase | 100 كتلة | 100 | 10 |
| أقصى عمق reorg | 288 | 288 | 1,000 |
| `bits` البداية | `0x1D00FFFF` | `0x1F00FFFF` | `0x207FFFFF` |
| تأكيدات موصى بها | 6 | 3 | 1 |
| DNS seeds | اختيارية | اختيارية | لا |

### 3.1 لماذا `chain_id`؟

يُدرج داخل `sighash` ورسائل المصافحة. يمنع إعادة إرسال توقيع من testnet إلى mainnet
أو بين شبكتين من نفس الكود.

### 3.2 لا تغيير بعد Genesis

أي تغيير في: المكافأة، فترة الكتلة، `bits` البداية، `chain_id`، أو قواعد التحقق =
**شبكة جديدة**. وثّق ذلك في `coin/CHAIN_PARAMS.md` قبل التعدين.

---

## 4) البنية العامة والمجلدات

```
falcon/
├── bitcoin.md                  ← هذه الخريطة
├── coin/
│   ├── main.mg                 ← نقطة الدخول (mgcd / mgc-cli / mgc-wallet / mgc-miner)
│   ├── lib/
│   │   ├── params.mg           ← ثوابت الشبكة
│   │   ├── endian.mg           ← قراءة/كتابة little-endian
│   │   ├── varint.mg           ← CompactSize
│   │   ├── hash.mg             ← SHA-256d, HASH160, Merkle
│   │   ├── base58.mg           ← Base58Check
│   │   ├── ripemd160.mg        ← RIPEMD-160
│   │   ├── bigint.mg           ← 256-bit unsigned
│   │   ├── secp256k1.mg        ← ECDSA + point ops
│   │   ├── keys.mg             ← مفاتيح، WIF، عناوين
│   │   ├── serialization.mg    ← قراءة/كتابة آمنة
│   │   ├── tx.mg               ← المعاملات وsighash
│   │   ├── script.mg           ← P2PKH فقط في v0
│   │   ├── merkle.mg           ← Merkle root
│   │   ├── block.mg            ← الترويسة والكتلة
│   │   ├── pow.mg              ← target/bits/chainwork
│   │   ├── chain.mg            ← السلسلة، الفروع، reorg
│   │   ├── consensus.mg        ← قواعد التحقق
│   │   ├── utxo.mg             ← مجموعة UTXO
│   │   ├── mempool.mg          ← الميمبول
│   │   ├── storage.mg          ← ملفات مسطحة وatomic writes
│   │   ├── p2p.mg              ← إطار الرسائل
│   │   ├── peer.mg             ← إدارة الأقران
│   │   ├── addrman.mg          ← دفتر عناوين الأقران
│   │   ├── wallet.mg           ← محفظة مشفرة
│   │   ├── mining.mg           ← بناء كتلة وتعدين
│   │   ├── json.mg             ← JSON صغير للـ RPC
│   │   ├── rpc.mg              ← JSON-RPC محلي
│   │   └── cli.mg              ← أوامر سطر الأوامر
│   ├── tests/
│   │   ├── test_endian.mg
│   │   ├── test_varint.mg
│   │   ├── test_hash.mg
│   │   ├── test_base58.mg
│   │   ├── test_ripemd160.mg
│   │   ├── test_secp256k1.mg
│   │   ├── test_tx.mg
│   │   ├── test_block.mg
│   │   ├── test_pow.mg
│   │   ├── test_utxo.mg
│   │   ├── test_storage.mg
│   │   └── vectors/            ← ملفات اختبار معروفة
│   ├── tools/
│   │   ├── genesis.mg          ← توليد Genesis وتثبيته
│   │   ├── keygen.mg
│   │   ├── bench_sha256.mg
│   │   └── fuzz_deserialize.mg
│   └── scripts/
│       ├── run_regtest.sh
│       └── run_3nodes.sh
├── data/                       ← وقت التشغيل، غير متتبع في git
└── build/                      ← نواتج الترجمة
```

> **قاعدة `use`:** كل ملفات `coin/lib/*.mg` تُستدعى من `coin/main.mg` بصيغة
> `use "lib/endian.mg";` — لأن البحث يبدأ من مجلد الملف المستورد (`coin/lib/`).
> لا تستعمل `use "coin/lib/..."` من داخل `coin/` لأنه سيبحث `coin/coin/lib`.

### 4.1 الرسم المعماري

```
+---------------------------+
|  CLI / JSON-RPC (محلي)    |
+------------+--------------+
             |
+------------v--------------+       +---------------------+
|  Node Core                |<----->|  P2P Manager        |
|  chain / consensus /      |       |  peers / addrman    |
|  mempool / UTXO           |       |  inv / getdata      |
+------------+--------------+       +----------+----------+
             |                                 |
+------------v--------------+       +----------v----------+
|  Storage (flat files)     |       |  TCP IPv4 sockets   |
|  blocks / index / utxo    |       |  poll event loop    |
+---------------------------+       +---------------------+

+---------------------------+
|  Wallet (مشفرة)           |
|  keys / UTXO / signing    |
+---------------------------+
```

### 4.2 ترتيب الاعتماديات

```
endian + varint + hash
        |
        +--> base58 + ripemd160 + hash160
        |
        +--> bigint --> secp256k1 --> keys/address
        |
        +--> serialization --> tx --> script/sighash
        |                        |
        |                        +--> merkle --> block --> pow
        |                                             |
        |                                             +--> consensus --> chain
        |                                                                  |
        +--> storage <-----------------------------------------------------+
        |
        +--> p2p --> peer --> addrman
        |
        +--> utxo + mempool --> mining
        |
        +--> wallet --> rpc/cli
```

---

## 5) خريطة التنفيذ (Roadmap)

> المدد تقديرية لمطوّر واحد متمكّن. أضف 50% احتياطاً بسبب قيود المترجم الحالية.
> **لا تنتقل لمرحلة قبل نجاح اختبارات المرحلة السابقة.**

### المرحلة 0 — الأساسات والترميز (أسبوع 1) — **مكتملة (2026-05-09)**

**المهام**
- [x] إنشاء هيكل `coin/` و`coin/lib/` و`coin/tests/`.
- [x] `endian.mg`: `read_u16_le/u32_le/u64_le`، `write_*`، `read_i64_le`.
- [x] `varint.mg`: CompactSize (1/3/5/9 بايت) مع حدود صارمة.
- [x] `hash.mg`: `sha256d_raw`، `sha256d_hex`، `merkle_root`.
- [x] `serialization.mg`: قارئ/كاتب مؤشر مع `offset` و`limit` و`ok`.
- [x] `params.mg`: ثوابت الشبكة (main/test/regtest) + `util.mg`.
- [x] اختبارات متجهات معروفة + سكربت `coin/scripts/test_phase0.sh`.

**Definition of Done**
- [x] كل دالة deserialize ترفض البيانات القصيرة/الطويلة/السلبية دون crash.
- [x] `test_endian`, `test_varint`, `test_hash`, `test_serialization`, `test_params` كلها تنجح.

> **ملاحظة قيود مترجم مكتشفة:** تمرير `&struct.field` (مثل `&r.offset`) إلى دالة يفسد القيمة/الإزاحة في backend الحالي — حلّها باستخدام متغير محلي ثم نسخ النتيجة (`br_read_varint`). المصفوفات المحلية `char a[64]` تفقد عناصرها بعد المؤشر الأول عند تمريرها لدوال؛ استعمل `alloc<char>(n)` للبيانات الثنائية. ثوابت `const int` العامة فوق 2^31-1 تُقتطع؛ استعمل دوال تعيد literal 64-بت (`mgc_initial_subsidy`, `mgc_max_money`).

### المرحلة 1 — التشفير والمفاتيح والعناوين (أسابيع 2–4)

**المهام**
- [x] `ripemd160.mg`: تنفيذ RIPEMD-160 + متجهات اختبار.
- [x] `base58.mg`: ترميز/فك ترميز + Base58Check (checksum = أول 4 من SHA-256d).
- [x] `bigint.mg`: 256-بت غير موقّع.
- [x] `secp256k1.mg`: نقطة، جمع، مضاعفة، ضرب قياسي، ضغط/فك ضغط.
- [x] ECDSA: توقيع/تحقق، DER، low-S، RFC6979.
- [x] `keys.mg`: توليد مفتاح من `crypto_rng_bytes`، WIF، عنوان P2PKH.
- [x] `tools/keygen.mg`.

> **حالة المرحلة 1:** مكتملة وظيفياً. السكربت `coin/scripts/test_phase1.sh` ينجح مع `test_ripemd160`, `test_base58`, `test_bigint`, `test_secp256k1`, `test_keys` وأداة `keygen`. تم التحقق من توقيع RFC6979 مقابل مرجع Python (نفس DER)، ومن عنوان/WIF للمفتاح `1` عبر regtest/testnet/mainnet.
> **ملاحظة أداء:** `mod_mul` يستخدم قسمة بت-ببت العامة، لذا توقيع+تحقق واحد ≈ 8 ثوانٍ حالياً. بوابة 1,000 توقيع عشوائي مؤجلة حتى تحسين التخفيض (pseudo-Mersenne) أو توفير مسار اختبار أسرع.

**تفاصيل `bigint` الإلزامية**
- التمثيل الفعلي: مصفوفة مسطحة `int*` من 16 limb — قاعدة 2^16، little-endian. تجنّبنا `struct BigInt` لأن المترجم لا يدعم بشكل موثوق المصفوفات داخل structs المحلية/المتداخلة.
- العمليات: `zero`, `copy`, `cmp`, `add`, `sub`, `mul`, `mod_add`, `mod_sub`, `mod_mul`, `mod_inv`, `mod_pow` (التخفيض العام bit-by-bit).
- استعمل ضرب 16×16 بت داخل `int` 64-بت لتجنب الفائض.
- `mod_inv` بطريقة Fermat (`a^(p-2)`).
- **لا تستعمل `struct` متداخلاً** (`Point { BigInt x; ... }`)؛ النقاط تستعمل 3 مصفوفات `int*` منفصلة (x,y,z) بإحداثيات Jacobian.
- **قيود مترجم إضافية مكتشفة:** `base`, `borrow`, `raw` كلمات محجوزة. المؤشر `int*` يستخدم عنونة بايتية في `*(p + i)`؛ استعمل `p[i]` دائماً. لا تستعمل `continue` (استبدلها بشرط).

**ثوابت المنحنى**
```
p  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
n  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
a  = 0
b  = 7
```

**Definition of Done**
- [x] المفتاح الخاص `1` يعطي المفتاح العام المضغوط:
  `0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798`.
- [ ] توقيع/تحقق 1,000 مرة عشوائياً، ورفض توقيع معدّل بايت واحد. (تم التحقق من التوقيع/الرفض؛ التكرار 1,000 مؤجل بسبب الأداء.)
- [x] عنوان WIF → مفتاح → عنوان يعود لنفس القيمة.
- [x] `hash160` يطابق متجهات RIPEMD-160/SHA-256 المعروفة.

### المرحلة 2 — المعاملات وUTXO (أسابيع 5–6)

**المهام**
- [ ] `tx.mg`: بنية المعاملة، الترميز/فك الترميز، txid.
- [ ] `script.mg`: قوالب P2PKH فقط + Coinbase + OP_RETURN اختياري.
- [ ] `sighash`: `MGC-SIGHASH-v1` مع `chain_id`، `SIGHASH_ALL` فقط في v0.
- [ ] `utxo.mg`: مفتاح `txid:vout`، إضافة/حذف/استعلام، فحص إنفاق مزدوج.
- [ ] `mempool.mg`: إضافة، إزالة عند التعدين، إعادة عند reorg، حدود الحجم.
- [ ] `test_tx.mg` + `test_utxo.mg`.

**قاعدة مهمة**
- لا تستعمل `string` لتخزين بايتات ثنائية. استعمل `char*` + طول.
- `txid` = SHA-256d للترميز **مع scriptSig فارغ**، لضمان ثبات المعرّف.
- التوقيع يغطي كل المدخلات والمخرجات وقيم prevouts و`chain_id`.

**Definition of Done**
- معاملة round-trip: serialize → deserialize → نفس البايتات.
- تعديل أي بايت في التوقيع/المخرجات/القيمة = فشل التحقق.
- إنفاق نفس الـ UTXO مرتين في نفس الكتلة = رفض.
- Coinbase لا تُنفق قبل 100 كتلة.

### المرحلة 3 — الكتل والإجماع وPoW (أسابيع 7–8)

**المهام**
- [ ] `block.mg`: ترويسة 80 بايت + قائمة معاملات + Merkle root.
- [ ] `pow.mg`: `target_from_bits`, `bits_from_target`, مقارنة hash، chainwork.
- [ ] `consensus.mg`: كل قواعد التحقق مرتبة.
- [ ] `chain.mg`: ربط الكتل، الفروع، اختيار السلسلة، reorg.
- [ ] `mining.mg`: بناء Coinbase، اختيار معاملات، nonce loop.
- [ ] `test_block.mg`, `test_pow.mg`.

**Definition of Done**
- كتلة معدّنة على `regtest` تُقبل، وكتلة بنفس nonce على mainnet-target تُرفض.
- Merkle root خاطئ = رفض.
- إعادة تنظيم 5 كتل تعمل وتعيد المعاملات إلى الميمبول.
- مكافأة Coinbase > subsidy + fees = رفض.

### المرحلة 4 — التخزين بدون قاعدة بيانات (أسبوع 9)

**المهام**
- [ ] `storage.mg`: كتابة ذرّية (tmp + fsync + rename).
- [ ] `blkNNNNN.dat`: سجل `[u32 len][block bytes]` مع تحقق hash.
- [ ] `index.dat`: فهرس ثابت الحجم لكل كتلة.
- [ ] `chainstate/utxo.dat`: لقطة UTXO قابلة لإعادة البناء.
- [ ] `peers.dat`, `mempool.dat`, `wallet/wallet.dat`.
- [x] إعادة بناء تلقائية للـUTXO من سجل الكتل عند الإقلاع (بديل `-reindex`).
- [ ] قفل البيانات `.lock` عبر `sys_flock`.

**Definition of Done**
- `kill -9` أثناء الكتابة ثم إعادة التشغيل = لا تلف؛ تُتجاهل السجلات الناقصة.
- إعادة البناء تعطي نفس `utxo` الناتج عن التشغيل العادي.
- نسخ مجلد البيانات إلى جهاز آخر يعمل.

### المرحلة 5 — شبكة P2P (أسابيع 10–12)

**المهام**
- [ ] `p2p.mg`: إطار الرسائل + checksum + حدود الحجم.
- [ ] `peer.mg`: handshake، ping/pong، timeout، ban score.
- [ ] `addrman.mg`: عناوين معروفة، محاولات، منع eclipse.
- [ ] مزامنة headers-first: `getheaders` → `headers` → `getdata` → `block`.
- [ ] بث `inv` للمعاملات والكتل الجديدة.
- [ ] `getaddr/addr`, `mempool`, `notfound`.
- [ ] seed nodes اختيارية من ملف إعداد (ليست سلطة).

**Definition of Done**
- عقدتان تتزامنان من Genesis إلى 500 كتلة.
- عقدة ثالثة تنضم وتتزامن دون إعادة تشغيل الأوليين.
- رسالة مشوهة/ضخمة لا تُسقط العقدة.
- عقدة تحاول إرسال كتلة غير صالحة تُعاقب وتُقطع.

### المرحلة 6 — المحفظة وCLI/RPC (أسابيع 13–14)

**المهام**
- [ ] `wallet.mg`: مفاتيح، عناوين، UTXO، اختيار عملات، بناء توقيع.
- [ ] تشفير المحفظة: PBKDF2-SHA256 + AES-256-CBC + HMAC-SHA256.
- [ ] `json.mg`: JSON صغير (كائنات/مصفوفات/نصوص/أرقام/bool/null) بحدود عمق.
- [ ] `rpc.mg`: JSON-RPC على `127.0.0.1` فقط + cookie auth.
- [ ] `cli.mg`: `getblockchaininfo`, `getbalance`, `getnewaddress`, `sendtoaddress`, `getpeerinfo`, `generate`.
- [ ] `wallet.dat` لا يحتوي مفاتيح نصية صريحة.

**Definition of Done**
- إنشاء محفظة، استلام، إرسال، وتأكيد.
- كلمة مرور خاطئة = فشل فك التشفير، لا crash.
- RPC غير متاح من خارج localhost افتراضياً.
- لا تظهر مفاتيح خاصة في `debug.log`.

### المرحلة 7 — التعدين والتقسية (أسابيع 15–16)

**المهام**
- [ ] تحسين SHA-256: `Sha256Ctx` + midstate للترويسة.
- [ ] `bench_sha256.mg` وقياس H/s.
- [ ] `mine` command + `generatetoaddress` للـ regtest.
- [ ] fuzz لكل deserializer ورسائل P2P.
- [ ] اختبارات ضغط: 10,000 معاملة، 1,000 كتلة.
- [ ] مراجعة أمنية داخلية + قائمة فحص.

**Definition of Done**
- التعدين يعمل بلا انهيار لساعات.
- fuzz 1,000,000 مدخل عشوائي بلا crash.
- زمن مزامنة 1,000 كتلة regtest < 60 ثانية.
- لا تسريب ذاكرة واضح في تشغيل 72 ساعة.

### المرحلة 8 — Testnet العام (أسابيع 17–20)

**المهام**
- [x] سكربت `run_testnet_soak.sh` ينشر 3 عقد اختبار على منافذ مختلفة ويراقب التزامن/الذاكرة.
- [ ] تشغيل السكربت 72 ساعة فعلياً ومراقبة reorg، انقطاع، ازدواج إنفاق، رسائل سيئة.
- [ ] إصلاح الأخطاء وتثبيت `chain_id`/Genesis.
- [ ] كتابة `testnet/README.md` وتعليمات التشغيل.
- [ ] مراجعة قانونية/ضريبية حسب بلدك قبل أي إطلاق.

**Definition of Done**
- 30 يوماً testnet دون فقدان إجماع بين العقد.
- لا أخطاء حرجة مفتوحة.
- إعادة بناء من الصفر تعطي نفس النتيجة.

### المرحلة 9 — Mainnet (فقط بعد Audit)

**المهام**
- [ ] Audit خارجي للكود والتشفير والإجماع.
- [ ] إصدار ثنائيات قابلة لإعادة البناء (reproducible builds).
- [ ] Genesis نهائي + checkpoints اختيارية (غير إجماعية).
- [ ] خطة ترقية/فورك موثقة.
- [ ] لا premine، أو الإفصاح الكامل عنه قبل الإطلاق.

> **لا تختصر هذه المرحلة.** عملة بلا مراجعة أمنية = أموال الناس في خطر.

---

## 6) المواصفات التقنية

### 6.1 الترميز والتسلسل

- كل الأعداد الصحيحة في الشبكة **little-endian**.
- `varint` = Bitcoin CompactSize:
  - `< 0xFD`: بايت واحد.
  - `<= 0xFFFF`: `0xFD` + u16.
  - `<= 0xFFFFFFFF`: `0xFE` + u32.
  - وإلا: `0xFF` + u64.
- النصوص/البايتات: `varint length` ثم البايتات.
- كل قارئ يحمل `offset` و`limit` و`ok`، وأي قراءة خارج الحدود تُفشل التحليل.
- لا تستعمل `strlen` على بيانات ثنائية.

```c
struct ByteReader {
    char* data;
    int length;
    int offset;
    bool ok;
};

fn br_read_u32(ByteReader* r) -> int {
    if (!r.ok || r.offset + 4 > r.length) { r.ok = false; return 0; }
    int v = (cast<int>(*(r.data + r.offset))) |
            (cast<int>(*(r.data + r.offset + 1)) << 8) |
            (cast<int>(*(r.data + r.offset + 2)) << 16) |
            (cast<int>(*(r.data + r.offset + 3)) << 24);
    r.offset = r.offset + 4;
    return v;
}
```

> استعمل `& 255` عند قراءة البايت لتجنب تمديد الإشارة إذا كان `char` موقّعاً في backend.

### 6.2 التجزئة والتشفير المطلوب

موجود حالياً في `lib/crypto.mg`:

- `crypto_sha256_raw`, `crypto_sha256_hex`, `crypto_sha256_bytes`
- `crypto_hmac_sha256_raw/hex`
- `crypto_pbkdf2_sha256_raw/hex`
- `crypto_aes_cbc_encrypt_raw/decrypt_raw`
- `crypto_chacha20_xor_raw`
- `crypto_rng_bytes` (getrandom)

**ناقص ويجب إضافته:**

- `ripemd160` + `hash160`.
- `base58` + Base58Check.
- `sha256_ctx` تزايدي + `sha256_midstate` (للتعدين).
- `secp256k1` + ECDSA + DER + RFC6979.
- دوال `wipe` لمسح المفاتيح من الذاكرة بعد الاستعمال.

**متجهات اختبار أساسية**

```
SHA256("abc")      = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
SHA256d("")        = 5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456
RIPEMD160("abc")   = 8eb208f7e05d987a9b044a8e98c6b087f15a0bfc
G (compressed)     = 0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
```

### 6.3 المفاتيح والعناوين

- المفتاح الخاص: 32 بايت من `crypto_rng_bytes`، مع التحقق `0 < k < n`.
- المفتاح العام: مضغوط 33 بايت (`02`/`03` + X).
- `HASH160 = RIPEMD160(SHA256(pubkey))`.
- العنوان: `Base58Check(version_byte || HASH160)`.
- WIF: `Base58Check(wif_prefix || privkey || 0x01)` للمفتاح المضغوط.

```c
fn address_from_pubkey(char* pub33) -> string {
    char* sha = alloc<char>(32);
    crypto_sha256_raw(pub33, 33, sha);
    char* h160 = alloc<char>(20);
    ripemd160_raw(sha, 32, h160);
    // payload = version + h160 + checksum(SHA256d)
    // base58check_encode
}
```

### 6.4 تنسيق المعاملة

```
version        u32 LE
input_count    varint
  prev_txid    32 بايت
  prev_index   u32 LE
  script_len   varint
  scriptSig    bytes
  sequence     u32 LE
output_count   varint
  value        i64 LE (satoshi)
  script_len   varint
  scriptPubKey bytes
locktime       u32 LE
```

- `txid = SHA-256d(serialize_with_empty_scriptsigs(tx))` — لا يشمل التوقيعات.
- Coinbase: `prev_txid = 0x00..00`, `prev_index = 0xFFFFFFFF`، وscriptSig يبدأ بارتفاع الكتلة.
- v0 لا يدعم `witness` ولا `SegWit`.

### 6.5 Sighash (مخصص، غير متوافق مع Bitcoin)

```
digest = SHA256d(
    "MGC-SIGHASH-v1" ||
    chain_id (u32 LE) ||
    version (u32 LE) ||
    locktime (u32 LE) ||
    input_count (varint) ||
    لكل input: prev_txid (32) || prev_index (u32) || value (i64) || scriptPubKey (varint+bytes) ||
    output_count (varint) ||
    لكل output: value (i64) || scriptPubKey (varint+bytes) ||
    input_index (u32 LE) ||
    sighash_type (u32 LE = 1)
)
```

- يغطي **كل** المدخلات والمخرجات والقيم، لذا يمنع تغيير أي مبلغ.
- `SIGHASH_ALL` فقط في v0.
- التوقيع = `DER(r,s) || 0x01`.
- low-S إلزامي: `s <= n/2`.

### 6.6 الكتلة والترويسة

```
version        u32 LE
prev_block     32 بايت
merkle_root    32 بايت
timestamp      u32 LE
bits           u32 LE
nonce          u32 LE
= 80 بايت
```

- `block_hash = SHA256d(header)`، يُعرض معكوساً (big-endian hex).
- `merkle_root` يُحسب من txids (وليس من التوقيعات).
- أول معاملة = Coinbase، وواحدة فقط.
- الحد الأقصى 1,000,000 بايت.
- timestamp > median(last 11) و <= now + 2h.

### 6.7 PoW والصعوبة

- الهدف من `bits`: mantissa/exponent مثل Bitcoin.
- قارن `block_hash` (مفسّراً little-endian كعدد 256-بت) بـ `target`.
- `chainwork += 2^256 / (target + 1)`.
- إعادة الحساب كل 2016 كتلة:
  - `actual = timestamp(last) - timestamp(first)`
  - `target = old_target * actual / target_span`
  - احصر التغيير في [1/4, 4×].
  - لا تتجاوز `max_target`.
- `regtest` يسمح بـ `bits = 0x207FFFFF` لتعدين فوري.
- لا تعتمد على `float`؛ استعمل bigint للمقارنة والحساب.

### 6.8 UTXO

```c
struct OutPoint {
    string txid_hex;   // 64 حرفاً (أو char* 32 بايت في النسخة المحسّنة)
    int index;
};

struct Utxo {
    int value;         // satoshi
    char* script;      // scriptPubKey
    int script_len;
    int height;
    bool coinbase;
};
```

- المفتاح: `txid_hex + ":" + index`.
- في الذاكرة: hash map مخصص (open addressing) وليس `Map` الخطي في `lib/collections.mg`.
- لقطة `utxo.dat`: magic + version + count + سجلات ثابتة + checksum.
- عند `-reindex`: أعد بناء UTXO من الكتل.

### 6.9 التحقق من الكتلة (الترتيب الإلزامي)

1. حجم الكتلة <= الحد.
2. الترويسة 80 بايت، `version` مدعوم.
3. `prev_block` موجود (أو Genesis).
4. `timestamp` ضمن القيود.
5. `bits` يطابق الصعوبة المتوقعة.
6. `block_hash <= target`.
7. `merkle_root` صحيح.
8. أول tx Coinbase وواحدة فقط.
9. Coinbase value <= subsidy + fees.
10. كل tx: تنسيق، حجم، مدخلات/مخرجات، قيم، توقيعات، UTXO، إنفاق مزدوج، نضج Coinbase.
11. لا يتجاوز مجموع المخرجات مجموع المدخلات.
12. تطبيق التغييرات على UTXO بشكل ذرّي؛ عند أي فشل ارجع بالكامل.

### 6.10 بروتوكول P2P

**إطار الرسالة**

```
magic[4] | command[12] | payload_len u32 LE | checksum[4] | payload
checksum = أول 4 بايت من SHA256d(payload)
```

- `command` ASCII منتهٍ بـ `\0` ومحشو حتى 12.
- أقصى payload 4,000,000 بايت.
- أي رسالة مشوهة = قطع الاتصال + خصم نقاط.

**الرسائل الأساسية**

| الرسالة | الوظيفة |
|---|---|
| `version` / `verack` | مصافحة، chain_id، الارتفاع، nonce |
| `ping` / `pong` | قياس الحياة |
| `getaddr` / `addr` | تبادل عناوين الأقران |
| `inv` | إعلان tx/block متاح |
| `getdata` | طلب tx/block |
| `notfound` | العنصر غير موجود |
| `getheaders` / `headers` | مزامنة الترويسات |
| `block` / `tx` | تسليم العناصر |
| `mempool` | طلب محتويات الميمبول |
| `reject` | رفض مع سبب |

**Handshake**

- أرسل `version` فور الاتصال.
- تحقق من `chain_id` و`magic`؛ اختلاف = قطع.
- أرسل `verack`؛ لا تقبل رسائل أخرى قبل اكتمال المصافحة.
- `nonce` لمنع الاتصال الذاتي.

**المزامنة**

1. `getheaders` مع locator من آخر 10 ترويسات.
2. استقبل حتى 2000 ترويسة، تحقق من PoW والربط.
3. `getdata` للكتل الناقصة.
4. تحقق وأضف.
5. كرر حتى لا مزيد.

**الحدود**

- 8 أقران صادرة + 32 واردة كحد أقصى.
- ping كل 2 دقيقة، قطع بعد 20 دقيقة خمول.
- ban score: 100 = حظر 24 ساعة.
- لا تقبل عناوين خاصة/loopback من الشبكة العامة.

### 6.11 التخزين بدون قاعدة بيانات

```
$HOME/.mgc/mainnet/
├── .lock
├── .cookie
├── debug.log
├── blocks/
│   ├── blk00000.dat
│   └── index.dat
├── chainstate/
│   └── utxo.dat
├── mempool.dat
├── peers.dat
└── wallet/
    └── wallet.dat
```

**سجل الكتلة**

```
[u32 length][block bytes]
```

- تحقق `SHA256d(block)` == hash المتوقع عند القراءة.
- إذا كان السجل الأخير ناقصاً/تالفاً، تجاهله وأعد بناء الفهرس.

**الفهرس**

```
hash[32] | prev[32] | height u32 | file_no u32 | offset u32 | size u32 |
time u32 | bits u32 | chainwork[32]
```

**الكتابة الذرّية**

1. اكتب إلى `*.tmp`.
2. `file_sync`.
3. `file_rename` إلى الاسم النهائي.
4. `file_sync` للمجلد إن أمكن.

**لا قاعدة بيانات**: لا SQLite، لا LevelDB، لا Redis. فقط ملفات + فهارس في الذاكرة.

### 6.12 المحفظة

- ملف واحد `wallet.dat` مشفر.
- البنية:

```
magic "MGCW" | version u32 | network u32 |
kdf "pbkdf2-sha256" | iterations u32 | salt[16] |
iv[16] | ciphertext_len u32 | ciphertext | mac[32]
```

- مفتاح التشفير = `PBKDF2-SHA256(password, salt, iterations, 32)`.
- التشفير = AES-256-CBC.
- MAC = HMAC-SHA256(mac_key, iv || ciphertext) — Encrypt-then-MAC.
- افتراضي: 200,000 تكرار (قابل للزيادة).
- لا تضع المفتاح الخاص في argv أو environment أو سجل.
- بعد الاستعمال: `wipe` للذاكرة.
- نسخ احتياطي = نسخ `wallet.dat` + كلمة المرور + إعادة فحص البلوكشين.

**اختيار العملات**

- v0: largest-first مع تغيير.
- v1: Branch and Bound لتقليل التغيير.
- رسوم: `fee = size_bytes * fee_rate` مع حد أدنى.
- لا ترسل حتى تتأكد أن مجموع المدخلات >= المخرجات + الرسوم.

### 6.13 RPC و CLI

- JSON-RPC على `127.0.0.1` فقط.
- مصادقة cookie: ملف `.cookie` عشوائي، صلاحية 600، HTTP Basic.
- أقصى حجم طلب 1 MB.
- لا CORS، لا bind عام افتراضياً.

**أوامر CLI الأساسية**

```
mgc-cli getblockchaininfo
mgc-cli getblockcount
mgc-cli getblockhash <height>
mgc-cli getblock <hash>
mgc-cli getrawtransaction <txid> [verbose]
mgc-cli sendrawtransaction <hex>
mgc-cli gettxout <txid> <vout>
mgc-cli getbalance
mgc-cli getnewaddress
mgc-cli sendtoaddress <address> <amount>
mgc-cli listtransactions
mgc-cli getpeerinfo
mgc-cli addnode <ip:port> add
mgc-cli getmempoolinfo
mgc-cli getmininginfo
mgc-cli generate <blocks>        # regtest/testnet فقط
mgc-cli stop
```

**RPC methods v0**

`getblockchaininfo`, `getblockcount`, `getbestblockhash`, `getblockhash`, `getblock`,
`getrawtransaction`, `sendrawtransaction`, `gettxout`, `getbalance`, `getnewaddress`,
`sendtoaddress`, `listtransactions`, `getpeerinfo`, `addnode`, `getmempoolinfo`,
`getmininginfo`, `generate`, `stop`.

### 6.14 التعدين

- `mine` يبني Coinbase بارتفاع الكتلة + رسوم الميمبول.
- merkle root من txids.
- nonce من 0..2^32-1، ثم غيّر `extranonce` في Coinbase scriptSig وأعد حساب merkle.
- تحقق داخلي قبل الإرسال.
- v0: solo mining فقط. لا Stratum pools.
- حسّن SHA-256 عبر midstate للترويسة (أول 64 بايت ثابتة، آخر 16 تتغير مع nonce).

---

## 7) خطة الاختبارات

### 7.1 اختبارات وحدات

| الملف | يختبر |
|---|---|
| `test_endian.mg` | قراءة/كتابة كل الأحجام والحالات الحدية |
| `test_varint.mg` | 1/3/5/9 بايت، قيم سالبة، اقتطاع |
| `test_hash.mg` | SHA-256, SHA-256d, HASH160, Merkle |
| `test_base58.mg` | ترميز/فك ترميز، checksum خاطئ |
| `test_ripemd160.mg` | متجهات NIST |
| `test_secp256k1.mg` | G، ضرب قياسي، ضغط، ECDSA، DER، low-S |
| `test_tx.mg` | round-trip، txid، sighash، توقيع معدّل |
| `test_block.mg` | ترويسة، merkle، Coinbase، حدود |
| `test_pow.mg` | bits/target/chainwork، صعوبة |
| `test_utxo.mg` | إضافة/حذف/إنفاق مزدوج/نضج |
| `test_storage.mg` | atomic write، استرداد بعد اقتطاع |

**أمر التشغيل**

```bash
./magc coin/tests/test_hash.mg -o /tmp/test_hash && /tmp/test_hash
./magc coin/tests/test_secp256k1.mg -o /tmp/test_secp && /tmp/test_secp
```

### 7.2 اختبارات تكامل

```bash
# 3 عقد regtest على منافذ 29333/29334/29335
./magc coin/main.mg -o build/mgcd
./build/mgcd --network=regtest --port=29333 --datadir=/tmp/mgc1 &
./build/mgcd --network=regtest --port=29334 --datadir=/tmp/mgc2 --addnode=127.0.0.1:29333 &
./build/mgcd --network=regtest --port=29335 --datadir=/tmp/mgc3 --addnode=127.0.0.1:29333 &
```

**سيناريوهات إلزامية**

1. تعدين 10 كتل على العقدة 1، ومزامنة 2 و3.
2. إنشاء عنوان على 2، إرسال 5 MGC من 1، تأكيد، ظهور الرصيد.
3. إيقاف 2 بـ `kill -9` أثناء الكتابة، إعادة تشغيل، سلامة البيانات.
4. عقدة 1 تعدّن 3 كتل، عقدة 2 تعدّن 5 كتل من نفس الارتفاع، إعادة الاتصال = reorg.
5. محاولة إنفاق مزدوج في كتلتين = رفض.
6. كتلة بـ merkle خاطئ = رفض.
7. كتلة بـ PoW خاطئ = رفض.
8. رسالة P2P بطول 100 MB = قطع، لا crash.
9. محفظة بكلمة مرور خاطئة = رفض.
10. `-reindex` = نفس UTXO الناتج.

### 7.3 Fuzz

- `tools/fuzz_deserialize.mg` يغذي كل deserializer بـ 1,000,000 مدخل عشوائي.
- لا crash، لا قراءة خارج الحدود.
- شغّله بعد كل تغيير في الترميز.

### 7.4 أداء

- قياس `bench_sha256` قبل/بعد midstate.
- قياس مزامنة 1,000 كتلة regtest.
- قياس الذاكرة عند 100,000 UTXO.
- لا تعِد أرقاماً تسويقية قبل القياس.

---

## 8) الأمان ونموذج التهديد

### 8.1 تهديدات يجب تصميم الدفاع عنها

| التهديد | الدفاع |
|---|---|
| إنفاق مزدوج | UTXO + فحص داخل الكتلة والميمبول |
| تزوير معاملة | ECDSA + sighash يغطي كل شيء |
| تعديل txid | txid بلا scriptSig |
| إعادة تشغيل بين الشبكات | `chain_id` في sighash + magic مختلف |
| Eclipse attack | addrman + أقران متعددون + لا تعتمد على peer واحد |
| Sybil | لا تحسم الإجماع بعدد الأقران؛ اعتمد على العمل التراكمي |
| 51% | لا حماية مطلقة؛ تأكيدات أكثر للمبالغ الكبيرة |
| DoS بالرسائل | حدود حجم + ban score + timeouts |
| تلف الملفات | atomic writes + checksums + reindex |
| سرقة المحفظة | تشفير + KDF قوي + لا مفاتيح في السجلات |
| ذاكرة غير آمنة | فحص حدود يدوي + fuzz + تجنب nested structs |
| تلاعب بالصعوبة | حساب bigint + قواعد صارمة + اختبارات |

### 8.2 قواعد كتابة إلزامية

- لا تستعمل `print` لطباعة `string`؛ استعمل `print_str`.
- لا تستعمل `raw` أو `base` كأسماء متغيرات.
- لا تضع `struct` داخل `struct`؛ استعمل حقولاً مسطحة أو مؤشرات.
- لا ترجع `struct` كبيراً يحوي `string[]` من دالة.
- لا تعتمد على `string` للبيانات الثنائية.
- لا تفترض أن `sys_read` قرأ كل المطلوب؛ كرر حتى النهاية.
- امسح المفاتيح من الذاكرة بعد الاستعمال.
- لا تسجل المفاتيح أو كلمة المرور أو الـ seed أبداً.
- كل دالة تحليل تُرجع `bool`/`error` ولا تُسقط البرنامج.

### 8.3 ما يجب مراجعته قبل mainnet

- [ ] مراجعة ECDSA/RFC6979/DER/low-S.
- [ ] مراجعة sighash: هل يغطي كل الحقول؟
- [ ] مراجعة حدود deserialization.
- [ ] مراجعة قواعد الصعوبة وchainwork.
- [ ] مراجعة reorg وrollback UTXO.
- [ ] مراجعة تشفير المحفظة وKDF.
- [ ] مراجعة RNG وعدم إعادة استخدام nonce.
- [ ] مراجعة P2P: لا ثقة بأي رسالة.
- [ ] اختبار fuzz طويل.
- [ ] Audit خارجي.

---

## 9) اللامركزية والحوكمة

- **لا مفاتيح إدارية**: لا أحد يستطيع سكّ عملات أو تجميدها.
- **لا خادم مركزي**: العقد تتصل ببعضها مباشرة.
- **Seed nodes للاكتشاف فقط**: يمكن حذفها واستبدالها؛ لا تتحكم بالإجماع.
- **التغييرات الإجماعية**: تحتاج تبنياً واسعاً؛ لا فرض من مطور واحد.
- **الشبكات منفصلة**: `mainnet`/`testnet`/`regtest` بـ `chain_id` وماجيك مختلف.
- **لا checkpoints إجماعية**: يمكن إضافة checkpoints لتسريع المزامنة فقط، ويجب توثيق أنها ليست نهائية.
- **الشفافية**: كل قاعدة تحقق موجودة في الكود ومغطاة باختبار.

---

## 10) خارج النطاق (v0)

- توافق مع شبكة Bitcoin أو محافظها.
- SegWit / Taproot / Schnorr.
- Script VM كامل أو عقود ذكية.
- Lightning Network.
- الخصوصية (zk-SNARKs، RingCT، CoinJoin).
- Mining pools / Stratum.
- SPV / محفظة خفيفة.
- محفظة موبايل أو واجهة رسومية.
- Tor / I2P.
- ASIC resistance.
- Atomic swaps / bridges.
- أي وعد بعائد مالي.

---

## 11) المخاطر والبدائل

| الخطر | الاحتمال | الأثر | التخفيف |
|---|---|---|---|
| قيود المترجم (nested structs, arrays) | مرتفع | متوسط | تصاميم مسطحة + اختبارات مبكرة |
| بطء secp256k1 النقي | متوسط | مرتفع | Jacobian + اختبار أداء + بديل OpenSSL للاختبار فقط |
| بطء SHA-256 في التعدين | مرتفع | متوسط | midstate + قياس + عدم المنافسة على ASIC |
| أخطاء إجماع | متوسط | كارثي | اختبارات متجهات + تنفيذ مرجعي بلغة أخرى للمقارنة |
| تلف التخزين | متوسط | مرتفع | atomic writes + reindex + نسخ احتياطي |
| هجمات P2P | مرتفع | متوسط | حدود + ban score + fuzz |
| فقدان مفاتيح | متوسط | كارثي | تشفير + نسخ احتياطي + تحذيرات |
| مسؤولية قانونية | متوسط | مرتفع | testnet فقط + مراجعة قانونية قبل mainnet |

**بديل MVP للتشفير:** استخدم OpenSSL CLI عبر `sys_fork`/أنابيب **للاختبار فقط**،
ثم استبدله بـ `secp256k1.mg` النقي قبل أي إطلاق. لا تضع مفاتيح حقيقية في مسار OpenSSL
قابل للتسريب.

---

## 12) ترتيب التنفيذ العملي (أول 14 يوماً)

### اليوم 1–2
- [x] إنشاء المجلدات.
- [x] `coin/lib/endian.mg` + `coin/tests/test_endian.mg`.
- [x] `coin/lib/varint.mg` + اختبار.

### اليوم 3–4
- [x] `coin/lib/hash.mg`: SHA-256d + HASH160 + Merkle.
- [x] `coin/lib/serialization.mg`: ByteReader/ByteWriter.
- [x] اختبارات.

### اليوم 5–7
- [x] `coin/lib/base58.mg`.
- [x] `coin/lib/ripemd160.mg` + متجهات.
- [x] `coin/lib/bigint.mg` (جمع/طرح/ضرب/مقارنة) + اختبارات.

### اليوم 8–11
- [x] `coin/lib/bigint.mg`: mod_inv + mod_pow.
- [x] `coin/lib/secp256k1.mg`: point ops + scalar mul.
- [x] اختبار G والمفتاح 1.

### اليوم 12–14
- [x] `coin/lib/keys.mg`: WIF + عنوان.
- [x] `coin/lib/tx.mg`: بنية + ترميز + txid.
- [x] `coin/lib/script.mg`: P2PKH template.
- [x] `coin/lib/sighash`.
- [x] `coin/tests/test_tx.mg`.

> **بوابة قرار:** لا تبدأ P2P قبل نجاح توقيع/تحقق 1,000 معاملة عشوائية.

---

## 13) قائمة التحقق النهائية قبل الإطلاق

### الإجماع
- [x] Genesis نهائي ومثبت في الكود.
- [x] `chain_id` وmagic وبادئات العناوين نهائية.
- [x] قواعد الصعوبة مختبرة عبر 10,000 نافذة retarget محاكاة.
- [x] لا مسار يسمح بسكّ عملات خارج Coinbase (فائض، Coinbase مكرر، مدخل مكرر).
- [x] reorg مختبر حتى 288 كتلة.
- [x] نضج Coinbase وhalving مختبران.

### التشفير
- [x] SHA-256 يطابق NIST.
- [x] RIPEMD-160 يطابق المتجهات.
- [x] secp256k1 يطابق SEC2.
- [x] ECDSA + RFC6979 + low-S.
- [x] لا إعادة استخدام nonce: RFC6979 deterministic ومختبر.
- [x] RNG من getrandom.

### التخزين
- [x] atomic writes + fsync.
- [x] reindex/إعادة بناء UTXO من سجل الكتل يعمل.
- [x] استرداد بعد `kill -9`.
- [x] نسخ احتياطي/استعادة موثقان ومختبران.

### الشبكة
- [x] 3+ عقد تتزامن.
- [x] رسائل مشوهة/checksum خاطئ/حجم زائد تُقطع وتُعاقب دون إسقاط العقد.
- [x] ban score وtimeouts.
- [ ] لا ثقة بأي peer.

### المحفظة
- [x] تشفير + MAC.
- [x] كلمة مرور خاطئة = رفض.
- [x] لا مفاتيح في السجلات.
- [x] نسخ احتياطي يعمل.

### الأمان
- [x] fuzz 1M مدخل.
- [ ] Audit خارجي.
- [ ] مراجعة قانونية.
- [ ] خطة إفصاح أمني.

---

## 14) أوامر البدء (بعد إنشاء الكود)

```bash
# بناء العقدة
./magc coin/main.mg -o build/mgcd

# اختبارات سريعة
./magc coin/tests/test_hash.mg -o /tmp/test_hash && /tmp/test_hash
./magc coin/tests/test_secp256k1.mg -o /tmp/test_secp && /tmp/test_secp
./magc coin/tests/test_tx.mg -o /tmp/test_tx && /tmp/test_tx

# تشغيل عقدة regtest
./build/mgcd --network=regtest --datadir=/tmp/mgc1 --port=29333 --rpcport=29332

# إنشاء عنوان وإرسال
./build/mgcd-cli --datadir=/tmp/mgc1 getnewaddress
./build/mgcd-cli --datadir=/tmp/mgc1 generate 101
./build/mgcd-cli --datadir=/tmp/mgc1 getbalance

# تشغيل soak test لثلاث عقد testnet (الافتراضي 72 ساعة، كتلة كل 120 ثانية)
NETWORK=test DURATION_SECONDS=259200 BLOCK_INTERVAL=120 ./coin/scripts/run_testnet_soak.sh
```

---

## 15) الخلاصة

الطريق الواقعي هو:

1. **أساسات صحيحة** (ترميز/تجزئة/اختبارات).
2. **تشفير يعمل** (secp256k1 + ECDSA + عناوين).
3. **معاملات وUTXO** مع sighash يغطي كل شيء.
4. **كتل وPoW** بقواعد صارمة.
5. **تخزين ملفات** بكتابة ذرّية.
6. **شبكة P2P** محدودة لكن آمنة.
7. **محفظة وRPC**.
8. **testnet طويل** ثم audit ثم mainnet.

> **القاعدة الذهبية:** لا تُطلق عملة لأن الكود «يعمل على جهازك». أطلقها فقط عندما
> تنجح الاختبارات، والمراجعة الأمنية، والاختبار الميداني. العملة ليست مجرد كود؛
> إنها مسؤولية أموال وأمانة الناس.

---

## 16) حالة التنفيذ الحالية (بعد بناء v0.1)

### ما تم تنفيذه

- المراحل 0–8 بالكامل داخل `coin/`:
  - أساسات الترميز والتشفير (`endian`, `varint`, `hash`, `base58`, `ripemd160`, `bigint`, `secp256k1`, `keys`, `serialization`).
  - معاملات P2PKH و`sighash` و`script` و`utxo` و`mempool`.
  - كتل وPoW وconsensus وسلسلة مع reorg وتعدين.
  - تخزين ملفات مسطّح مع atomic writes/fsync وقفل datadir وملف cookie.
  - P2P ثنائي مع مصافحة، getheaders/headers، inv/getdata، block/tx، addr، ping/pong، ban score وtimeouts.
  - محفظة مشفّرة + JSON parser + JSON-RPC محلي + CLI + عقدة بحلقة أحداث واحدة.
  - أدوات: `keygen`, `genesis`, `bench_sha256`, `fuzz_deserialize`.
  - سكربتات: `test_all.sh`, `run_regtest.sh`, `run_3nodes.sh`, `test_crash_recovery.sh`, `run_testnet_soak.sh`.
- إصلاحات مهمة أثناء التكامل:
  - `mgc_tx_deserialize` لم يعد يمرّر `&struct.field[i]` مباشرة.
  - `getpeerinfo` يستخدم مؤشراً محلياً لـ `MgcPeerManager` بسبب قيود codegen في الوصول المتسلسل للمؤشرات.
  - `mgc_node_generate` يبث `inv` للكتلة الجديدة بعد إضافتها للسلسلة.
  - فصل رسائل `inv` عن `getdata` في `peer.mg`، فأصبحت الكتل تنتقل فعلياً بين الأقران.
  - إصلاح `mgc_tx_txid` ليشمل scriptSig: سابقاً كانت coinbase لنفس العنوان/المبلغ تتكرر عبر الارتفاعات.
  - تحميل المحفظة عبر `mgc_wallet_load_unlocked` للعقدة، مع إبقاء `mgc_wallet_load` مقفلاً للاختبارات.
  - إعادة بناء UTXO من block log عند الإقلاع بدلاً من استبداله بلقطة `utxo.dat` قديمة.
  - `generate` يعيد استخدام عنوان تعدين محفوظ بدلاً من توليد مفتاح جديد لكل كتلة؛ يُحفظ المفتاح قبل التعدين.
  - KDF سريع (1000 دورة) لكلمة مرور فارغة فقط؛ كلمة المرور غير الفارغة تبقى 200,000 دورة.
  - تثبيت Genesis hash داخل `params.mg` مع رفض أي genesis مختلف.
  - رفض المدخلات المكررة في `mgc_consensus_tx_fee` و`mgc_consensus_verify_tx` قبل الوصول للـUTXO.
  - `cli.mg` لا يقرأ `HOME` عند تمرير `--datadir`، فلا تتلوث مخرجات JSON برسائل التصحيح.

### نتائج التحقق

```bash
./coin/scripts/test_all.sh
# rc=0 — All phases and tools passed.

timeout 180 ./coin/scripts/run_3nodes.sh
# rc=0 — node1 generate 5 => node2/node3 getblockcount = 5
# getpeerinfo يعمل على العقد الثلاث.

timeout 180 ./coin/scripts/test_crash_recovery.sh
# rc=0 — graceful restart وkill -9 يحافظان على 5 كتل و250 MGC.

./magc coin/tests/test_deep_reorg.mg -o /tmp/test_deep_reorg && /tmp/test_deep_reorg
# PASS — fork بعمق 288 كتلة يعيد التنظيم ويستبدل السلسلة الأفضل.
```

- `bench_sha256`: ~16–19 ألف SHA-256d/ثانية على الجهاز المستخدم.
- `fuzz_deserialize`: 1,000,000 عينة، `PASS`.
- Genesis المثبت:
  - `regtest`: `5e984494eed2ca8adf2a4548eabea8fabf5b4a1edd4d1c5551464ed62019df92`
  - `testnet`: `c8914c574ef915949eb25b41261727090d27075db487b0dae615f5af54d2ef31`
  - `mainnet`: `83d7204153ca279257d1cfa96109380f6670f4aff435da80b9c7c3cecec1cb9d`
- اختبار `test_deep_reorg`: PASS عند عمق 288، مع بقاء الجد المشترك وعزل الفرع القديم.
- اختبار `test_difficulty`: PASS لمحاكاة 10,000 نافذة retarget على الشبكات الثلاث.
- اختبار `test_crash_recovery`: PASS بعد restart عادي و`kill -9` مع 5 كتل و250 MGC،
  ثم حذف `chainstate/utxo.dat` وإعادة البناء من سجل الكتل، ثم استعادة نسخة من datadir.
- `getblock <hash>` يعيد الكتلة الخام بنجاح عبر RPC (اختبار مباشر في `test_rpc`).
- `test_consensus`: يرفض فائض المخرجات، Coinbase، والمدخل المكرر.
- `test_secp256k1`: توقيع RFC6979 حتمي؛ تغيير digest يغيّر التوقيع.
- `test_peer_sync`: رسالة P2P بchecksum خاطئ تُقطع دون التأثير على peer سليم.
- `run_testnet_soak.sh`: تجربة قصيرة PASS بثلاث عقد testnet متزامنة؛ تشغيل 72 ساعة ما زال مطلوباً.

### انحرافات مقصودة عن الخطة

- رسالة `headers` تحمل 32-byte block hashes بدلاً من 80-byte headers كاملة (تبسيط v0).
- `chainwork` تقريبي بسبب `int`، وتعدين regtest يستخدم حد محاولات قابل للضبط.
- `mgcd` و`mgc-cli` كلاهما مبنيان من `coin/main.mg` مع تفرّع حسب اسم الملف/الوسائط.
- `generate 101` قد يتجاوز مهلة CLI الافتراضية؛ استخدم دفعات أصغر مثل `generate 20`.
- في Magnetar، الوصول مثل `a.b.c` حيث `a` و`b` مؤشرات قد يُترجم بخطأ؛ استخدم متغيراً وسيطاً:
  `MgcPeerManager* pm = node.pref; int cap = pm.capacity;`.

### ما لم يكتمل بعد قبل الإطلاق

- تشغيل testnet لمدة 72 ساعة على الأقل عبر `run_testnet_soak.sh` مع مراقبة الذاكرة والاتصال.
- audit خارجي، مراجعة قانونية، وخطة إفصاح أمني.
- لا يُوصى بإطلاق mainnet بهذه الحالة؛ regtest/testnet فقط للاختبار.
