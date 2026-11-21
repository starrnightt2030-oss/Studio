import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'wav.dart';

/// موسيقى خلفية (ألحان أصلية متولّدة للتطبيق — من غير حقوق).
class MusicTrack {
  const MusicTrack(this.id, this.title, this.mood);
  final String id;
  final String title;
  final String mood;
  String get asset => 'assets/audio/music/$id.wav';
}

class SfxDef {
  const SfxDef(this.id, this.title);
  final String id;
  final String title;
  String get asset => 'assets/audio/sfx/$id.wav';
}

class AudioLibrary {
  AudioLibrary._();

  static const music = <MusicTrack>[
    MusicTrack('ad_upbeat', 'إعلاني حماسي', 'طاقة · 120 BPM'),
    MusicTrack('kids_playful', 'طفولي مرح', 'قصص وكرتون'),
    MusicTrack('corporate_inspire', 'مؤسسي ملهم', 'شرح تطبيقات وشركات'),
    MusicTrack('calm_story', 'هادي للحكايات', 'قبل النوم وكتب'),
    MusicTrack('drama_cinematic', 'درامي سينمائي', 'وثائقي وتشويق'),
  ];

  static const sfx = <SfxDef>[
    SfxDef('whoosh', 'ووش'),
    SfxDef('pop', 'بوب'),
    SfxDef('ding', 'دينج'),
    SfxDef('magic', 'سحر ✨'),
    SfxDef('boing', 'بوينج (كرتون)'),
    SfxDef('success', 'نجاح'),
    SfxDef('impact', 'خبطة'),
    SfxDef('riser', 'تصاعد'),
    SfxDef('applause', 'تصفيق'),
    SfxDef('tick', 'تكتكة ساعة'),
  ];

  static MusicTrack? musicById(String? id) => id == null ? null : music.where((m) => m.id == id).firstOrNull;
  static SfxDef? sfxById(String? id) => id == null ? null : sfx.where((s) => s.id == id).firstOrNull;

  static final _cache = <String, Uint8List>{};

  static Future<Uint8List> load(String asset) async {
    final hit = _cache[asset];
    if (hit != null) return hit;
    final data = await rootBundle.load(asset);
    return _cache[asset] = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

class SfxCue {
  const SfxCue(this.wav, this.at, {this.gain = 0.8});
  final Uint8List wav;
  final Duration at;
  final double gain;
}

/// ميكسر: صوت + موسيقى بتوطى لوحدها تحت الكلام (Ducking) + مؤثرات في أماكنها.
class Mixer {
  Mixer._();

  /// مقدمة موسيقى قبل الكلام، وذيل بعده.
  static const lead = Duration(milliseconds: 1200);
  static const tail = Duration(milliseconds: 2200);

  static Uint8List mix({
    required Uint8List voiceWav,
    Uint8List? musicWav,
    double musicVolume = 0.25,
    bool duck = true,
    List<SfxCue> sfx = const [],
  }) {
    final voice = Wav.decode(voiceWav);
    final rate = voice.sampleRate;
    final hasMusic = musicWav != null;
    final leadN = hasMusic ? (rate * lead.inMilliseconds / 1000).round() : 0;
    final tailN = hasMusic ? (rate * tail.inMilliseconds / 1000).round() : 0;
    final n = leadN + voice.samples.length + tailN;
    final out = Float64List(n);

    for (var i = 0; i < voice.samples.length; i++) {
      out[leadN + i] = voice.samples[i] / 32768.0;
    }

    if (hasMusic) {
      final m = _resample(Wav.decode(musicWav), rate);
      final gains = duck ? _duckEnvelope(out, rate) : null;
      final fadeIn = (rate * 0.6).round();
      final fadeOut = (rate * 1.8).round();
      for (var i = 0; i < n; i++) {
        var g = musicVolume;
        if (gains != null) g *= gains[i];
        if (i < fadeIn) g *= i / fadeIn;
        if (i > n - fadeOut) g *= (n - i) / fadeOut;
        out[i] += (m.samples[i % m.samples.length] / 32768.0) * g;
      }
    }

    for (final c in sfx) {
      final s = _resample(Wav.decode(c.wav), rate);
      final start = leadN + (rate * c.at.inMilliseconds / 1000).round();
      for (var i = 0; i < s.samples.length; i++) {
        final j = start + i;
        if (j < 0 || j >= n) continue;
        out[j] += (s.samples[i] / 32768.0) * c.gain;
      }
    }

    // حماية من التقطيع
    var peak = 0.0;
    for (final v in out) {
      if (v.abs() > peak) peak = v.abs();
    }
    final norm = peak > 0.98 ? 0.98 / peak : 1.0;
    final ints = Int16List(n);
    for (var i = 0; i < n; i++) {
      ints[i] = (out[i] * norm * 32767).round().clamp(-32768, 32767);
    }
    return Wav.encode(Pcm(ints, rate));
  }

  /// منحنى الـ Ducking: الموسيقى بتنزل لحوالي 30% وقت الكلام، وترجع بنعومة في الوقفات.
  static Float64List _duckEnvelope(Float64List voice, int rate) {
    final win = math.max(1, (rate * 0.02).round());
    final g = Float64List(voice.length);
    const ducked = 0.32;
    final attack = 1 - math.exp(-1 / (rate * 0.06));
    final release = 1 - math.exp(-1 / (rate * 0.45));
    var level = 1.0;
    var active = false;
    for (var i = 0; i < voice.length; i++) {
      if (i % win == 0) {
        var e = 0.0;
        final end = math.min(voice.length, i + win * 3);
        for (var j = i; j < end; j += 2) {
          e += voice[j] * voice[j];
        }
        active = math.sqrt(e / math.max(1, (end - i) / 2)) > 0.015;
      }
      final target = active ? ducked : 1.0;
      level += (target - level) * (target < level ? attack : release);
      g[i] = level;
    }
    return g;
  }

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
}
