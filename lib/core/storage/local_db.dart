import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// تخزين محلي على الجهاز (يشتغل على أندرويد والويب).
/// - settings: إعدادات بسيطة
/// - projects: المشاريع كـ JSON
/// - audio: ملفات الصوت المولّدة (WAV bytes) — كاش عشان مانولّدش نفس الجملة مرتين
class LocalDb {
  LocalDb._();

  static late Box settings;
  static late Box projects;
  static late Box audio;

  static Future<void> init() async {
    await Hive.initFlutter('studio_eldawly');
    settings = await Hive.openBox('settings');
    projects = await Hive.openBox('projects');
    audio = await Hive.openBox('audio');
  }

  static Uint8List? readAudio(String key) {
    final v = audio.get(key);
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    return null;
  }

  static Future<void> writeAudio(String key, Uint8List bytes) => audio.put(key, bytes);

  /// يمسح الصوت المتخزن اللي مش مستخدم في أي مشروع.
  static Future<int> pruneAudio(Set<String> keep) async {
    final remove = audio.keys.where((k) => !keep.contains(k)).toList();
    await audio.deleteAll(remove);
    return remove.length;
  }
}
