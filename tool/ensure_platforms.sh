#!/usr/bin/env bash
# يولّد مجلدات android/ و web/ لو مش موجودة، ويظبط اسم التطبيق وصلاحية الإنترنت.
# شغّله مرة واحدة على جهازك أو بيتشغّل تلقائياً في GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d web ]; then
  echo "• Generating platform folders (android, web)…"
  flutter create . --platforms=android,web --project-name studio_eldawly --org com.eldawly
fi

MANIFEST=android/app/src/main/AndroidManifest.xml
if [ -f "$MANIFEST" ]; then
  python3 - "$MANIFEST" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'android.permission.INTERNET' not in s:
    s = re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>', s, count=1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Studio-Eldawly"', s, count=1)
open(p, 'w', encoding='utf-8').write(s)
print('• AndroidManifest patched')
PY
fi

# MainActivity: قناة تصدير M4A (AAC) بمشفّر أندرويد
ACT=$(find android/app/src/main -name 'MainActivity.kt' | head -n1 || true)
if [ -n "${ACT:-}" ]; then
  PKG=$(grep -m1 '^package ' "$ACT" | awk '{print $2}')
  sed "s/__PACKAGE__/${PKG}/" tool/android/MainActivity.kt > "$ACT"
  echo "• MainActivity installed ($PKG)"
fi

# شاشة البداية الأصلية بنفس لون الانترو بدل الأبيض
for d in android/app/src/main/res/drawable android/app/src/main/res/drawable-v21; do
  if [ -d "$d" ]; then
    cat > "$d/launch_background.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item><color android:color="#070B17"/></item>
</layer-list>
XML
  fi
done

if [ -f web/index.html ]; then
  python3 - <<'PY'
import re, json
p = 'web/index.html'
s = open(p, encoding='utf-8').read()
s = re.sub(r'<title>.*?</title>', '<title>Studio-Eldawly | استوديو الصوت العربي</title>', s, count=1, flags=re.S)
s = s.replace('<html>', '<html lang="ar" dir="rtl">', 1)
if 'eldawly-bg' not in s:
    s = s.replace('</head>', '  <style id="eldawly-bg">html,body{background:#070B17;}</style>\n</head>', 1)
open(p, 'w', encoding='utf-8').write(s)
m = 'web/manifest.json'
d = json.load(open(m, encoding='utf-8'))
d.update({'name': 'Studio-Eldawly', 'short_name': 'Eldawly', 'background_color': '#070B17', 'theme_color': '#6C4DE6', 'description': 'استوديو تعليق صوتي عربي بالذكاء الاصطناعي'})
json.dump(d, open(m, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('• web patched')
PY
fi
