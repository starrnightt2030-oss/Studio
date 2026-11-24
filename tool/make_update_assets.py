#!/usr/bin/env python3
"""
يجهّز ملفات التحديث الصغيرة لـ Studio-Eldawly:

1. نسخة APK لكل معالج (arm64-v8a / armeabi-v7a) من الـ APK الكامل — بنفس رقم النسخة والتوقيع.
2. ملفات فرق (patch) من نسخ الـ APK اللي فاتت للنسخة الجديدة، فالموبايل بيحمّل المتغيّر بس.
3. checksums.json فيه بصمة SHA-256 لكل ملف عشان التطبيق يتأكد إن الناتج مطابق 100%.

صيغة الـ patch (ELDIFF01): نفس خوارزمية bsdiff، بس البلوكات مضغوطة zlib (أندرويد بيفكّها من غير مكتبات).
  [8] "ELDIFF01"  [8] ctrl_len  [8] diff_len  [8] new_size   (int64 little-endian)
  zlib(ctrl) zlib(diff) zlib(extra)
  ctrl = ثلاثيات int64 LE: (add_len, copy_len, seek)

usage: make_update_assets.py <universal.apk> <prev_dir> <out_dir>
env: KS_FILE KS_PASS KEY_ALIAS KEY_PASS
"""
import bz2
import glob
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import zipfile
import zlib
from multiprocessing import Pool

import bsdiff4

ABIS = ['arm64-v8a', 'armeabi-v7a']
ALL_ABIS = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86']


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def build_tool(name):
    root = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    tools = sorted(glob.glob(os.path.join(root, 'build-tools', '*', name)))
    if not tools:
        sys.exit(f'{name} not found')
    return tools[-1]


def split_abi(universal, abi, out):
    """يشيل مكتبات المعالجات التانية ويعيد المحاذاة والتوقيع."""
    raw = out + '.unsigned'
    drop = [f'lib/{a}/' for a in ALL_ABIS if a != abi]
    with zipfile.ZipFile(universal) as zin, zipfile.ZipFile(raw, 'w') as zout:
        for info in zin.infolist():
            n = info.filename
            if any(n.startswith(d) for d in drop):
                continue
            if n.startswith('META-INF/') and n.split('/')[-1].upper().endswith(('.SF', '.RSA', '.DSA', '.EC', 'MANIFEST.MF')):
                continue
            zout.writestr(info, zin.read(n), compress_type=info.compress_type)
    aligned = out + '.aligned'
    # محاذاة 16KB للمكتبات (build-tools 35+)، ولو مش مدعومة نستخدم محاذاة الصفحة العادية
    if subprocess.run([build_tool('zipalign'), '-f', '-P', '16', '4', raw, aligned]).returncode != 0:
        subprocess.run([build_tool('zipalign'), '-f', '-p', '4', raw, aligned], check=True)
    subprocess.run([
        build_tool('apksigner'), 'sign',
        '--ks', os.environ['KS_FILE'], '--ks-pass', 'env:KS_PASS',
        '--ks-key-alias', os.environ['KEY_ALIAS'], '--key-pass', 'env:KEY_PASS',
        '--out', out, aligned,
    ], check=True)
    os.remove(raw)
    os.remove(aligned)
    subprocess.run([build_tool('apksigner'), 'verify', out], check=True)


def _offtin(b):
    y = int.from_bytes(b[:7], 'little') | ((b[7] & 0x7F) << 56)
    return -y if b[7] & 0x80 else y


def to_eldiff(bsdiff_patch):
    assert bsdiff_patch[:8] == b'BSDIFF40'
    ctrl_len = _offtin(bsdiff_patch[8:16])
    diff_len = _offtin(bsdiff_patch[16:24])
    new_size = _offtin(bsdiff_patch[24:32])
    p = 32
    ctrl = bz2.decompress(bsdiff_patch[p:p + ctrl_len]); p += ctrl_len
    diff = bz2.decompress(bsdiff_patch[p:p + diff_len]); p += diff_len
    extra = bz2.decompress(bsdiff_patch[p:])
    triples = bytearray()
    for i in range(0, len(ctrl), 24):
        triples += struct.pack('<qqq', _offtin(ctrl[i:i + 8]), _offtin(ctrl[i + 8:i + 16]), _offtin(ctrl[i + 16:i + 24]))
    zc, zd, ze = zlib.compress(bytes(triples), 9), zlib.compress(diff, 9), zlib.compress(extra, 9)
    return b'ELDIFF01' + struct.pack('<qqq', len(zc), len(zd), new_size) + zc + zd + ze


def make_patch(job):
    base, target, out = job
    with open(base, 'rb') as f:
        old = f.read()
    with open(target, 'rb') as f:
        new = f.read()
    data = to_eldiff(bsdiff4.diff(old, new))
    with open(out, 'wb') as f:
        f.write(data)
    return out, len(data), len(new)


def main():
    universal, prev_dir, out_dir = sys.argv[1:4]
    os.makedirs(out_dir, exist_ok=True)
    shutil.copy(universal, os.path.join(out_dir, 'studio-eldawly.apk'))
    apks = {'universal': os.path.join(out_dir, 'studio-eldawly.apk')}
    for abi in ABIS:
        dst = os.path.join(out_dir, f'studio-eldawly-{abi}.apk')
        split_abi(universal, abi, dst)
        apks[abi] = dst

    checksums = {'apks': {}, 'patches': {}}
    for k, path in apks.items():
        checksums['apks'][k] = {'name': os.path.basename(path), 'sha256': sha256(path), 'size': os.path.getsize(path)}
        print(f'• {os.path.basename(path)}: {os.path.getsize(path) / 1048576:.1f} MB')

    # نسخ قديمة: كل APK في الإصدارات اللي فاتت (الكامل أو نفس المعالج)
    bases = sorted(set(glob.glob(os.path.join(prev_dir, '*', '*.apk'))))
    jobs, seen = [], set()
    for abi in ABIS:
        for base in bases:
            name = os.path.basename(base)
            if name not in ('studio-eldawly.apk', f'studio-eldawly-{abi}.apk'):
                continue
            bsha = sha256(base)
            if (abi, bsha) in seen:
                continue
            seen.add((abi, bsha))
            jobs.append((base, apks[abi], os.path.join(out_dir, f'patch-{abi}-{bsha[:16]}.eldiff')))

    with Pool(min(4, max(1, len(jobs)))) as pool:
        for out, size, full in pool.map(make_patch, jobs):
            name = os.path.basename(out)
            if size > full * 0.7:
                os.remove(out)
                print(f'  ✗ {name}: {size / 1048576:.1f} MB (مش موفّر — اتشال)')
                continue
            checksums['patches'][name] = {'size': size}
            print(f'  ✓ {name}: {size / 1048576:.1f} MB بدل {full / 1048576:.1f} MB')

    with open(os.path.join(out_dir, 'checksums.json'), 'w') as f:
        json.dump(checksums, f, indent=2)


if __name__ == '__main__':
    main()
