# نشر Studio-Eldawly على Google Play

## 1) اعمل مفتاح توقيع (مرة واحدة بس — واحتفظ بيه في مكان آمن)

على أي جهاز عليه Java:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

هيسألك على كلمة سر وبيانات بسيطة. **لو المفتاح ده ضاع، مش هتقدر تحدّث التطبيق على المتجر تاني**، فاعمل منه نسخة احتياطية.

## 2) ضيف المفتاح كـ Secrets في GitHub

حوّل الملف لنص:

```bash
base64 -w 0 upload-keystore.jks > keystore.txt     # على ماك: base64 -i upload-keystore.jks
```

وفي المشروع على GitHub: **Settings ← Secrets and variables ← Actions ← New repository secret**، وضيف:

| الاسم | القيمة |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | محتوى `keystore.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | كلمة سر الـ keystore |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | كلمة سر المفتاح |

من أول بناء بعدها، الـ APK والـ AAB هيتوقّعوا بالمفتاح الرسمي. من غير الـ Secrets، البناء بيتوقّع بمفتاح تجريبي (ينفع للتجربة بس).

## 3) نزّل ملف المتجر

**Actions ← آخر تشغيل ناجح ← Artifacts ← `Studio-Eldawly-AAB`** — ده الملف (`app-release.aab`) اللي بيترفع على Google Play Console.

## 4) Google Play Console

- **أيقونة 512×512:** `docs/store/icon-512.png`
- **صورة الغلاف 1024×500:** `docs/store/feature-graphic.png`
- **الوصف:** `docs/store-listing.md`
- **سياسة الخصوصية:** رابط ملف `docs/privacy-policy.md` على GitHub
- **صور الشاشة:** خدها من الموبايل (2 على الأقل، يفضّل 4–8)
- **تصنيف المحتوى ونموذج أمان البيانات:** التطبيق مفيهوش حسابات ولا إعلانات ولا تتبّع؛ النصوص بتتبعت لـ Google Gemini (وAzure لو المستخدم فعّله) عشان تتحوّل لصوت.

## 5) إصدار تحديث (بيظهر جوه التطبيق زي الرفيق)

1. انقل النسخة الحالية من `release.json` لأول `history` كـ `{ "v": "...", "notes": [...] }`.
2. ارفع `version` (مثلاً 1.3.0) واكتب في `notes` الجديد في النسخة دي بس.
3. ادفع على فرع `flutter-app`.

الـ CI بيبني الـ APK برقم النسخة (رقم البناء بيتحسب لوحده)، وبينشر Release اسمه `v1.3.0` فيه `studio-eldawly.apk` و`release.json`.
التطبيق بيشوف آخر Release أول ما يفتح وكل ما ترجعله، ويعرض «تحديث جديد» بالملاحظات، يحمّله بشريط تقدّم، وبعدين «تثبيت».
فيه كمان زرار «البحث عن تحديثات» في صفحة حسابي.

> التحديث بيتنشر بس لو مفتاح التوقيع متضاف في Secrets (الخطوة 2). من غيره كل بناء بيتوقّع بمفتاح مختلف، وأندرويد هيرفض يثبّت التحديث فوق القديم.
> نسخة المتجر (AAB) مفيهاش التحديث من جوه التطبيق — جوجل بلاي هو اللي بيحدّثها.

## نسخة الويب (اختياري)

**Settings ← Pages ← Source = GitHub Actions**، وبعدين **Actions ← Deploy Web to GitHub Pages ← Run workflow**.
