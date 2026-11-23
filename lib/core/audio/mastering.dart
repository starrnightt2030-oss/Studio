import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:glint_audio_pure/glint_audio_pure.dart';

import 'wav.dart';

/// مستوى الصوت النهائي حسب مكان النشر.
enum LoudnessTarget {
  social('سوشيال وإعلانات', -14),
  video('فيديو ويوتيوب', -16),
  podcast('بودكاست وكتب', -18),
  off('من غير توحيد', 0);

  const LoudnessTarget(this.label, this.lufs);
  final String label;
  final double lufs;
}

enum ExportFormat {
  mp3('MP3', 'حجم صغير · يشتغل في أي مكان', 'mp3', 'audio/mpeg'),
  wav('WAV 48kHz', 'أعلى جودة للمونتاج', 'wav', 'audio/x-wav');

  const ExportFormat(this.label, this.hint, this.ext, this.mime);
  final String label;
  final String hint;
  final String ext;
  final String mime;
}

class MasterResult {
  const MasterResult(this.pcm, this.trimmedStart);
  final Pcm pcm;

  /// قد إيه اتقص من أول الملف (عشان نظبط توقيت الترجمة).
  final Duration trimmedStart;
}

/// معالجة نهائية: قص الصمت، توحيد مستوى الصوت (تقريب لـ LUFS)، ليميتر ناعم، وتحويل لـ 48kHz.
class Mastering {
  Mastering._();

  static MasterResult process(Pcm input, {LoudnessTarget target = LoudnessTarget.video, int sampleRate = 48000, bool trim = true}) {
    var s = Float64List(input.samples.length);
    for (var i = 0; i < s.length; i++) {
      s[i] = input.samples[i] / 32768.0;
    }
    final rate = input.sampleRate;

    // 1) قص الصمت في الأول والآخر (مع هامش صغير)
    var trimmed = Duration.zero;
    if (trim && s.isNotEmpty) {
      const thr = 0.0056; // ≈ -45 dBFS
      final pad = (rate * 0.12).round();
      var a = 0;
      while (a < s.length && s[a].abs() < thr) {
        a++;
      }
      var b = s.length - 1;
      while (b > a && s[b].abs() < thr) {
        b--;
      }
      final from = math.max(0, a - pad);
      final to = math.min(s.length, b + pad);
      if (to > from) {
        trimmed = Duration(microseconds: (from * 1000000 / rate).round());
        s = Float64List.sublistView(s, from, to);
      }
    }

    // 2) توحيد المستوى: قياس متوسط الطاقة في بلوكات 400ms مع استبعاد الصمت (على طريقة BS.1770)
    if (target != LoudnessTarget.off && s.isNotEmpty) {
      final hp = _highPass(s, rate, 80);
      final block = (rate * 0.4).round();
      final hop = (rate * 0.1).round();
      final energies = <double>[];
      for (var i = 0; i + block <= hp.length; i += hop) {
        var e = 0.0;
        for (var j = i; j < i + block; j++) {
          e += hp[j] * hp[j];
        }
        energies.add(e / block);
      }
      if (energies.isEmpty) energies.add(hp.fold<double>(0, (a, v) => a + v * v) / hp.length);
      double lufsOf(Iterable<double> es) {
        final list = es.toList();
        if (list.isEmpty) return -70;
        final m = list.reduce((a, b) => a + b) / list.length;
        return -0.691 + 10 * math.log(math.max(m, 1e-12)) / math.ln10;
      }

      final abs = energies.where((e) => lufsOf([e]) > -70);
      final rel = lufsOf(abs) - 10;
      final gated = abs.where((e) => lufsOf([e]) > rel);
      final current = lufsOf(gated);
      final gain = math.pow(10, (target.lufs - current) / 20).toDouble().clamp(0.05, 12.0).toDouble();
      for (var i = 0; i < s.length; i++) {
        s[i] = _limit(s[i] * gain);
      }
    }

    // 3) تلاشي خفيف في الأطراف
    final fade = math.min((rate * 0.015).round(), s.length ~/ 2);
    for (var i = 0; i < fade; i++) {
      final g = i / fade;
      s[i] *= g;
      s[s.length - 1 - i] *= g;
    }

    // 4) تحويل التردد
    final out = _resample(s, rate, sampleRate);
    final ints = Int16List(out.length);
    for (var i = 0; i < out.length; i++) {
      ints[i] = (out[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return MasterResult(Pcm(ints, sampleRate), trimmed);
  }

  /// ليميتر ناعم: أي حاجة فوق 0.7 بتتضغط بنعومة وماتعديش ‎-0.1 dBFS.
  static double _limit(double x) {
    final a = x.abs();
    if (a <= 0.7) return x;
    final y = 0.7 + 0.288 * _tanh((a - 0.7) / 0.288);
    return x.isNegative ? -y : y;
  }

  static double _tanh(double v) {
    final e = math.exp(2 * v);
    return (e - 1) / (e + 1);
  }

  static Float64List _highPass(Float64List s, int rate, double cutoff) {
    final rc = 1 / (2 * math.pi * cutoff);
    final dt = 1 / rate;
    final alpha = rc / (rc + dt);
    final out = Float64List(s.length);
    var prevX = 0.0, prevY = 0.0;
    for (var i = 0; i < s.length; i++) {
      final y = alpha * (prevY + s[i] - prevX);
      out[i] = y;
      prevY = y;
      prevX = s[i];
    }
    return out;
  }

  /// تحويل معدل العينات (مع فلتر بسيط ضد التشويش لو بننزّل المعدل).
  static Float64List resample(Float64List s, int from, int to) {
    if (from > to && s.length > 8) {
      // FIR بسيط (نافذة Hann) قطعه عند ~0.9 من نص المعدل الجديد
      const taps = 15;
      final fc = 0.45 * to / from;
      final h = List<double>.generate(taps, (k) {
        final m = k - (taps - 1) / 2;
        final sinc = m == 0 ? 2 * fc : math.sin(2 * math.pi * fc * m) / (math.pi * m);
        return sinc * (0.5 - 0.5 * math.cos(2 * math.pi * k / (taps - 1)));
      });
      final sum = h.fold<double>(0, (a, b) => a + b);
      final f = Float64List(s.length);
      for (var i = 0; i < s.length; i++) {
        var acc = 0.0;
        for (var k = 0; k < taps; k++) {
          final j = i + k - (taps - 1) ~/ 2;
          if (j >= 0 && j < s.length) acc += s[j] * h[k];
        }
        f[i] = acc / sum;
      }
      s = f;
    }
    return _resample(s, from, to);
  }

  static Float64List _resample(Float64List s, int from, int to) {
    if (from == to || s.isEmpty) return s;
    final ratio = from / to;
    final n = (s.length / ratio).floor();
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      final x = i * ratio;
      final i0 = x.floor();
      final i1 = math.min(i0 + 1, s.length - 1);
      final f = x - i0;
      out[i] = s[i0] * (1 - f) + s[i1] * f;
    }
    return out;
  }

  static Future<(Uint8List, ExportFormat)> export(Uint8List wav, {required ExportFormat format, required LoudnessTarget target}) async {
    // كل الشغل (المعالجة + التشفير) في Isolate منفصل عشان الواجهة تفضل شغالة
    final bytes = await compute(_exportWorker, (wav, format.index, target.index));
    return (bytes, format);
  }

  /// وقت تقريبي للتحويل لـ MP3 (المشفّر بيشتغل أبطأ من مدة الصوت بحوالي الربع).
  static Duration estimate(Uint8List wav, ExportFormat format) {
    if (format != ExportFormat.mp3) return const Duration(seconds: 1);
    final d = Wav.durationOf(wav);
    return Duration(milliseconds: 1500 + (d.inMilliseconds * 0.35).round());
  }

  /// نفس قص الصمت اللي بيتعمل في التصدير (عشان توقيت الترجمة يطابق).
  static Duration leadingTrim(Uint8List wav) => process(Wav.decode(wav), target: LoudnessTarget.off, sampleRate: 24000).trimmedStart;
}

Uint8List _exportWorker((Uint8List, int, int) args) {
  final (wav, fi, ti) = args;
  final format = ExportFormat.values[fi];
  final target = LoudnessTarget.values[ti];
  if (format == ExportFormat.wav) {
    return Wav.encode(Mastering.process(Wav.decode(wav), target: target).pcm);
  }
  // MP3: ‏44.1kHz و128kbps — الجودة القياسية للـ MP3 وأسرع في التحويل
  final m = Mastering.process(Wav.decode(wav), target: target, sampleRate: 44100);
  final samples = m.pcm.samples;
  final pcm = Float64List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    pcm[i] = samples[i] / 32768.0;
  }
  return mp3EncodeMono(pcm, sampleRate: 44100, bitrate: 128);
}
