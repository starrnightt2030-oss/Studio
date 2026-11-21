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

## 5) تحديث الإصدار

قبل كل نسخة جديدة للمتجر زوّد الرقم في `pubspec.yaml`:

```yaml
version: 1.2.0+3   # الرقم بعد + لازم يزيد كل مرة
```

## نسخة الويب (اختياري)

**Settings ← Pages ← Source = GitHub Actions**، وبعدين **Actions ← Deploy Web to GitHub Pages ← Run workflow**.
