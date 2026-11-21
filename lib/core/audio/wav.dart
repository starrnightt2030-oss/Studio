import 'dart:math' as math;
import 'dart:typed_data';

/// صوت PCM 16-bit mono في الذاكرة.
class Pcm {
  Pcm(this.samples, this.sampleRate);
  final Int16List samples;
  final int sampleRate;

  Duration get duration => Duration(microseconds: (samples.length * 1000000 / sampleRate).round());
}

class Wav {
  Wav._();

  static bool isWav(Uint8List b) =>
      b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x41;

  /// يحوّل PCM خام (16-bit little endian) لملف WAV.
  static Uint8List fromPcm16(Uint8List pcm, {int sampleRate = 24000, int channels = 1}) {
    final header = ByteData(44);
    final dataLen = pcm.length;
    void str(int o, String s) {
      for (var i = 0; i < 4; i++) {
        header.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    header.setUint32(4, 36 + dataLen, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * 2, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    str(36, 'data');
    header.setUint32(40, dataLen, Endian.little);
    final out = Uint8List(44 + dataLen);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, 44 + dataLen, pcm);
    return out;
  }

  /// يقرا WAV (16-bit) ويرجّعه mono.
  static Pcm decode(Uint8List bytes) {
    if (!isWav(bytes)) {
      // نفترض PCM خام 24kHz لو مفيش هيدر
      final even = bytes.length - (bytes.length % 2);
      return Pcm(Int16List.view(Uint8List.fromList(bytes.sublist(0, even)).buffer), 24000);
    }
    final bd = ByteData.sublistView(bytes);
    var pos = 12;
    var channels = 1;
    var rate = 24000;
    var bits = 16;
    Int16List? samples;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      var size = bd.getUint32(pos + 4, Endian.little);
      final start = pos + 8;
      if (start + size > bytes.length) size = bytes.length - start;
      if (id == 'fmt ') {
        channels = bd.getUint16(start + 2, Endian.little);
        rate = bd.getUint32(start + 4, Endian.little);
        bits = bd.getUint16(start + 14, Endian.little);
      } else if (id == 'data') {
        if (bits != 16) throw const FormatException('Only 16-bit WAV is supported');
        final count = size ~/ 2;
        final raw = Int16List(count);
        for (var i = 0; i < count; i++) {
          raw[i] = bd.getInt16(start + i * 2, Endian.little);
        }
        samples = raw;
      }
      pos = start + size + (size.isOdd ? 1 : 0);
    }
    samples ??= Int16List(0);
    if (channels > 1) {
      final mono = Int16List(samples.length ~/ channels);
      for (var i = 0; i < mono.length; i++) {
        var sum = 0;
        for (var c = 0; c < channels; c++) {
          sum += samples[i * channels + c];
        }
        mono[i] = sum ~/ channels;
      }
      samples = mono;
    }
    return Pcm(samples, rate);
  }

  static Uint8List encode(Pcm pcm) => fromPcm16(
        pcm.samples.buffer.asUint8List(pcm.samples.offsetInBytes, pcm.samples.lengthInBytes),
        sampleRate: pcm.sampleRate,
      );

  static Pcm _resample(Pcm p, int rate) {
    if (p.sampleRate == rate || p.samples.isEmpty) return p;
    final ratio = p.sampleRate / rate;
    final n = (p.samples.length / ratio).floor();
    final out = Int16List(n);
    for (var i = 0; i < n; i++) {
      final x = i * ratio;
      final i0 = x.floor();
      final i1 = math.min(i0 + 1, p.samples.length - 1);
      final f = x - i0;
      out[i] = (p.samples[i0] * (1 - f) + p.samples[i1] * f).round();
    }
    return Pcm(out, rate);
  }

  /// يدمج كذا ملف WAV في ملف واحد مع مسافة صامتة بينهم، وتلاشي خفيف في الأطراف لمنع "التكة".
  static Uint8List concat(List<Uint8List> parts, {int gapMs = 250}) {
    if (parts.isEmpty) return fromPcm16(Uint8List(0));
    final decoded = parts.map(decode).toList();
    final rate = decoded.first.sampleRate;
    final list = decoded.map((p) => _resample(p, rate)).toList();
    final gap = (rate * gapMs / 1000).round();
    final total = list.fold<int>(0, (a, p) => a + p.samples.length) + gap * math.max(0, list.length - 1);
    final out = Int16List(total);
    var o = 0;
    final fade = (rate * 0.006).round();
    for (var k = 0; k < list.length; k++) {
      final s = list[k].samples;
      for (var i = 0; i < s.length; i++) {
        var v = s[i].toDouble();
        if (i < fade) v *= i / fade;
        if (i > s.length - fade) v *= (s.length - i) / fade;
        out[o + i] = v.round();
      }
      o += s.length;
      if (k < list.length - 1) o += gap;
    }
    return encode(Pcm(out, rate));
  }

  /// قمم الموجة للرسم (قيم من 0 لـ 1).
  static List<double> peaks(Uint8List wav, {int buckets = 48}) {
    final p = decode(wav);
    if (p.samples.isEmpty) return List.filled(buckets, 0.05);
    final per = math.max(1, p.samples.length ~/ buckets);
    final res = <double>[];
    var maxAll = 1;
    final raw = <int>[];
    for (var b = 0; b < buckets; b++) {
      var m = 0;
      final start = b * per;
      final end = math.min(start + per, p.samples.length);
      for (var i = start; i < end; i += 8) {
        final a = p.samples[i].abs();
        if (a > m) m = a;
      }
      raw.add(m);
      if (m > maxAll) maxAll = m;
    }
    for (final m in raw) {
      res.add(math.max(0.06, m / maxAll));
    }
    return res;
  }

  static Duration durationOf(Uint8List wav) => decode(wav).duration;
}
