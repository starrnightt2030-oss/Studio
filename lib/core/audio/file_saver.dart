import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// ملف جاهز للحفظ أو المشاركة.
class OutFile {
  const OutFile(this.bytes, this.name, this.mime);
  final Uint8List bytes;
  final String name;
  final String mime;
}

/// الحفظ في Download/Studio-Eldawly والمشاركة بامتداد صحيح.
class StudioFiles {
  StudioFiles._();

  static const folder = 'Studio-Eldawly';
  static const _channel = MethodChannel('eldawly/audio');

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// اسم ملف آمن ومميّز بالتاريخ والوقت عشان مايتكتبش فوق ملف قديم.
  static String fileName(String title, String ext) {
    final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_').trim();
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
    return '${clean.isEmpty ? 'Studio-Eldawly' : clean}_$stamp.$ext';
  }

  /// يحفظ الملفات في Download/Studio-Eldawly ويرجّع مكان الحفظ.
  static Future<String> saveToDownloads(List<OutFile> files) async {
    if (_android) {
      String? last;
      for (final f in files) {
        last = await _channel.invokeMethod<String>('saveToDownloads', {
          'bytes': f.bytes,
          'name': f.name,
          'mime': f.mime,
          'folder': folder,
        });
      }
      final p = last ?? 'Download/$folder';
      return p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : p;
    }
    // الويب وباقي المنصات: تنزيل/مشاركة عادية
    await share(files);
    return 'التنزيلات';
  }

  /// مشاركة بامتداد صحيح: على الموبايل بنكتب الملف مؤقتاً باسمه الحقيقي الأول.
  static Future<void> share(List<OutFile> files, {String? text}) async {
    if (kIsWeb) {
      await Share.shareXFiles([for (final f in files) XFile.fromData(f.bytes, mimeType: f.mime, name: f.name)], text: text);
      return;
    }
    final dir = Directory('${(await getTemporaryDirectory()).path}/$folder');
    if (!await dir.exists()) await dir.create(recursive: true);
    final xs = <XFile>[];
    for (final f in files) {
      final file = File('${dir.path}/${f.name}');
      await file.writeAsBytes(f.bytes, flush: true);
      xs.add(XFile(file.path, mimeType: f.mime, name: f.name));
    }
    await Share.shareXFiles(xs, text: text);
  }
}
