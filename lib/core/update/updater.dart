import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../storage/local_db.dart';

/// رقم النسخة بيتحط وقت البناء من release.json (CI بيبعته بـ --dart-define).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.2.0');

/// قناة التوزيع: github = نسخة APK بتحدّث نفسها، play = نسخة المتجر (المتجر هو اللي بيحدّثها).
const appChannel = String.fromEnvironment('CHANNEL', defaultValue: 'github');

class UpdateInfo {
  const UpdateInfo({
    required this.latest,
    required this.notes,
    required this.size,
    required this.apkUrl,
    this.apkSha,
    this.patchUrl,
    this.patchSize = 0,
    this.fullSize = 0,
  });
  final String latest;
  final List<String> notes;

  /// حجم الـ APK المناسب للموبايل ده.
  final int size;
  final String apkUrl;
  final String? apkSha;

  /// ملف الفرق (المتغيّر بس) لو متاح للنسخة المتثبّتة.
  final String? patchUrl;
  final int patchSize;

  /// حجم الـ APK الكامل (للمقارنة).
  final int fullSize;

  bool get isPatch => patchUrl != null;

  /// اللي هيتحمّل فعلاً.
  int get downloadSize => isPatch ? patchSize : size;
}

/// تحديثات من جوه التطبيق زي «الرفيق»: بنشوف آخر Release على GitHub،
/// نعرض الجديد، نحمّل الـ APK بشريط تقدّم، ونفتح شاشة التثبيت.
class Updater {
  Updater._();

  static const repo = 'starrnightt2030-oss/Studio';
  static const asset = 'studio-eldawly.apk';
  static const _channel = MethodChannel('eldawly/update');
  static final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(minutes: 5)));

  /// التحديث من جوه التطبيق متاح بس لنسخة APK على أندرويد.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && appChannel == 'github';

  static int compare(String a, String b) {
    List<int> parts(String v) => v.replaceFirst(RegExp('^v'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// ملاحظات النسخ الأحدث من اللي عندك ولحد النسخة اللي هتنزل بس.
  static List<String> notesBetween(Map<String, dynamic> release, String current, String latest) {
    final all = <Map>[
      {'v': release['version'], 'notes': release['notes']},
      ...((release['history'] as List?) ?? const []).cast<Map>(),
    ];
    return [
      for (final r in all)
        if (r['v'] != null && compare('${r['v']}', current) > 0 && compare('${r['v']}', latest) <= 0)
          for (final n in (r['notes'] as List? ?? const [])) '$n',
    ];
  }

  /// بيرجع null لو مفيش تحديث.
  static Future<UpdateInfo?> check() async {
    final res = await _dio.get<dynamic>(
      'https://api.github.com/repos/$repo/releases/latest',
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final j = (res.data is String ? jsonDecode(res.data as String) : res.data) as Map;
    final latest = '${j['tag_name'] ?? ''}'.replaceFirst(RegExp('^v'), '');
    if (latest.isEmpty || compare(latest, appVersion) <= 0) return null;
    final assets = (j['assets'] as List? ?? const []).cast<Map>();
    Map? named(String n) => assets.where((a) => a['name'] == n).firstOrNull;
    final universal = named(asset);
    if (universal == null) return null;

    // نختار APK المعالج بتاع الموبايل (أصغر بكتير)، وملف فرق لو فيه واحد للنسخة المتثبّتة
    Map? checksums;
    final cs = named('checksums.json');
    if (cs != null) {
      try {
        final r = await _dio.get<String>('${cs['browser_download_url']}', options: Options(responseType: ResponseType.plain));
        checksums = jsonDecode(r.data!) as Map;
      } catch (_) {}
    }
    Map? apk = universal;
    String? apkSha = (checksums?['apks'] as Map?)?['universal']?['sha256'] as String?;
    Map? patch;
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('apkInfo');
      final abi = '${info?['abi'] ?? ''}';
      final mine = named('studio-eldawly-$abi.apk');
      final mineSha = (checksums?['apks'] as Map?)?[abi]?['sha256'] as String?;
      if (mine != null && mineSha != null) {
        apk = mine;
        apkSha = mineSha;
        final base = '${info?['sha256'] ?? ''}';
        if (base.length >= 16) patch = named('patch-$abi-${base.substring(0, 16)}.eldiff');
      }
    } catch (_) {
      // أجهزة قديمة أو نسخة مفيهاش القناة: نكمّل بالكامل
    }
    var notes = <String>[];
    final rel = assets.where((a) => a['name'] == 'release.json').firstOrNull;
    if (rel != null) {
      try {
        final r = await _dio.get<String>('${rel['browser_download_url']}', options: Options(responseType: ResponseType.plain));
        notes = notesBetween(jsonDecode(r.data!) as Map<String, dynamic>, appVersion, latest);
      } catch (_) {}
    }
    return UpdateInfo(
      latest: latest,
      notes: notes,
      size: (apk!['size'] as num?)?.toInt() ?? 0,
      apkUrl: '${apk['browser_download_url']}',
      apkSha: apkSha,
      patchUrl: patch == null ? null : '${patch['browser_download_url']}',
      patchSize: (patch?['size'] as num?)?.toInt() ?? 0,
      fullSize: (universal['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// التنبيه بيظهر مرة واحدة لكل نسخة؛ بعدها التحديث متاح من الإعدادات.
  static bool wasShown(String v) => LocalDb.settings.get('updShown') == v;
  static Future<void> markShown(String v) => LocalDb.settings.put('updShown', v);

  static Future<String>? _running;

  /// تحميل التحديث جوه التطبيق (ضغطتين = تحميل واحد):
  /// ملف الفرق لو متاح (بيتركّب على النسخة المتثبّتة ويتأكد من البصمة)، وإلا الـ APK كامل.
  static Future<String> download(UpdateInfo info, void Function(int received, int total) onProgress, {void Function(String)? onStage}) {
    return _running ??= () async {
      try {
        final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
        if (await dir.exists()) await dir.delete(recursive: true);
        await dir.create(recursive: true);
        final path = '${dir.path}/studio-eldawly-${info.latest}.apk';
        if (info.isPatch && info.apkSha != null) {
          try {
            final patch = '${dir.path}/update.eldiff';
            await _dio.download(info.patchUrl!, patch, onReceiveProgress: (r, t) => onProgress(r, info.patchSize > 0 ? info.patchSize : t));
            if (info.patchSize > 0 && await File(patch).length() != info.patchSize) throw const FileSystemException('incomplete');
            onStage?.call('بيركّب التحديث…');
            await _channel.invokeMethod<bool>('applyPatch', {'patch': patch, 'out': path, 'sha256': info.apkSha});
            await File(patch).delete();
            return path;
          } catch (_) {
            // لو حصلت أي مشكلة نحمّل النسخة كاملة
            onStage?.call('بيحمّل النسخة كاملة…');
          }
        }
        var best = 0;
        await _dio.download(info.apkUrl, path, onReceiveProgress: (r, t) {
          final total = info.size > 0 ? info.size : t;
          if (r > best) {
            best = r;
            onProgress(r, total);
          }
        });
        final len = await File(path).length();
        if (len < 1000000 || (info.size > 0 && len != info.size)) {
          await File(path).delete();
          throw const FileSystemException('incomplete');
        }
        return path;
      } finally {
        _running = null;
      }
    }();
  }

  /// بيفتح شاشة التثبيت. بيرجع false لو لازم المستخدم يسمح بـ«تثبيت تطبيقات من المصدر ده» الأول.
  static Future<bool> install(String path) async {
    final r = await _channel.invokeMethod<String>('install', {'path': path});
    return r == 'ok';
  }

  static Future<void> openInBrowser(UpdateInfo? info) => launchUrl(
        Uri.parse(info?.apkUrl ?? 'https://github.com/$repo/releases/latest/download/$asset'),
        mode: LaunchMode.externalApplication,
      );
}
