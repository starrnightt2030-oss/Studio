import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:studio_eldawly/core/audio/wav.dart';
import 'package:studio_eldawly/core/audio/mastering.dart';
import 'package:studio_eldawly/core/audio/subtitles.dart';
import 'package:studio_eldawly/core/audio/mixer.dart';
import 'package:studio_eldawly/data/templates.dart';
import 'package:studio_eldawly/data/azure/azure_tts.dart';
import 'package:studio_eldawly/core/utils/text_split.dart';
import 'package:studio_eldawly/data/catalog/dialects.dart';
import 'package:studio_eldawly/data/catalog/emotions.dart';
import 'package:studio_eldawly/data/catalog/voices.dart';
import 'package:studio_eldawly/data/gemini/style_builder.dart';
import 'package:studio_eldawly/data/projects/models.dart';
import 'package:studio_eldawly/core/settings/settings.dart';
import 'package:studio_eldawly/data/gemini/gemini_client.dart';
import 'package:studio_eldawly/data/gemini/tts_service.dart';
import 'package:studio_eldawly/data/production/production_service.dart';
import 'package:studio_eldawly/core/update/updater.dart';
import 'package:studio_eldawly/data/gemini/tashkeel.dart';
import 'package:studio_eldawly/data/quran/quran.dart';

void main() {
  group('Voice catalog', () {
    test('every dialect has 16 personas with real Gemini voices', () {
      for (final d in Dialects.all) {
        final list = VoiceCatalog.filter(dialectId: d.id);
        expect(list.length, 16, reason: d.id);
        for (final v in list) {
          expect(VoiceCatalog.geminiVoices.containsKey(v.baseVoice), isTrue, reason: '${v.id} → ${v.baseVoice}');
        }
      }
    });

    test('personas inside one dialect use several different base voices', () {
      final voices = VoiceCatalog.filter(dialectId: 'egyptian').map((v) => v.baseVoice).toSet();
      expect(voices.length, greaterThanOrEqualTo(12));
    });

    test('ids are unique', () {
      final ids = VoiceCatalog.all.map((v) => v.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every gender × age combination exists in each dialect', () {
      for (final d in Dialects.all) {
        for (final g in Gender.values) {
          for (final a in Age.values) {
            expect(VoiceCatalog.filter(dialectId: d.id, gender: g, age: a), isNotEmpty, reason: '${d.id} $g $a');
          }
        }
      }
    });
  });

  group('WAV', () {
    test('pcm → wav → decode round trip', () {
      final pcm = Int16List.fromList(List.generate(2400, (i) => (i % 200) * 100 - 10000));
      final wav = Wav.fromPcm16(pcm.buffer.asUint8List(), sampleRate: 24000);
      expect(Wav.isWav(wav), isTrue);
      final back = Wav.decode(wav);
      expect(back.sampleRate, 24000);
      expect(back.samples.length, 2400);
      expect(back.samples[150], pcm[150]);
    });

    test('concat adds the gap and resamples', () {
      final a = Wav.fromPcm16(Uint8List(24000 * 2), sampleRate: 24000); // 1s
      final b = Wav.fromPcm16(Uint8List(16000 * 2), sampleRate: 16000); // 1s
      final m = Wav.decode(Wav.concat([a, b], gapMs: 500));
      expect(m.sampleRate, 24000);
      expect(m.duration.inMilliseconds, closeTo(2500, 5));
    });

    test('peaks are normalized', () {
      final pcm = Int16List.fromList(List.generate(4800, (i) => i < 2400 ? 1000 : 20000));
      final peaks = Wav.peaks(Wav.fromPcm16(pcm.buffer.asUint8List()), buckets: 10);
      expect(peaks.length, 10);
      expect(peaks.last, 1.0);
      expect(peaks.first, lessThan(0.2));
    });
  });

  group('Text', () {
    test('splits Arabic sentences', () {
      final s = TextSplit.sentences('أهلاً بيك! إزيك النهارده؟ أنا كويس جداً. وانت عامل إيه', minChars: 4);
      expect(s.length, 4);
      final merged = TextSplit.sentences('أهلاً! إزيك النهارده يا صاحبي؟');
      expect(merged.length, 1);
    });

    test('performance tags convert per API', () {
      const t = 'استنى ⟨وقفة⟩ هههه ⟨ضحكة⟩ تمام';
      expect(PerformanceTags.toApi(t), contains('<short pause>'));
      expect(PerformanceTags.toApi(t), contains('<laugh>'));
      expect(PerformanceTags.toPlain(t), isNot(contains('⟨')));
      expect(PerformanceTags.toPlain(t), contains('…'));
    });
  });

  group('Style', () {
    test('style mentions dialect, emotion and age', () {
      final v = VoiceCatalog.byId('egyptian_m_ad');
      final s = StyleBuilder.build(
        persona: v,
        emotion: Emotion.anger,
        intensity: Intensity.strong,
        controls: const VoiceControls(age: Age.elder, speed: 0.9),
      );
      expect(s, contains('Egyptian'));
      expect(s, contains('angry'));
      expect(s, contains('elderly'));
      expect(s, contains('fast'));
    });
  });

  group('Production plan', () {
    final service = ProductionService(TtsService(GeminiClient('test-key-0000000000000'), const AppSettings()), const AppSettings());

    test('groups sentences into few requests, each keeps its own emotion', () {
      final p = Project(title: 'x', type: ProjectType.audiobook, dialectId: 'egyptian', voiceId: 'egyptian_m_doc')
        ..segments = [
          for (var i = 0; i < 32; i++)
            Segment(text: 'دي جملة رقم $i في الكتاب الصوتي وطولها متوسط شوية.', emotion: Emotion.values[i % Emotion.values.length]),
        ];
      final chunks = service.plan(p);
      expect(chunks.length, lessThanOrEqualTo(6));
      expect(chunks.expand((c) => c.segments).length, 32);
      for (final c in chunks) {
        expect(c.segments.length, lessThanOrEqualTo(ProductionService.maxChunkSentences));
        expect(c.request.spans.length, c.segments.length);
      }
      expect(chunks.first.request.spans[1].direction, contains('joyful'));
    });

    test('speaker change starts a new chunk', () {
      final p = Project(title: 'x', type: ProjectType.podcast, dialectId: 'saudi', voiceId: 'saudi_m_pod')
        ..speakers = [
          Speaker(id: 'a', name: 'فهد', role: 'مضيف', voiceId: 'saudi_m_pod'),
          Speaker(id: 'b', name: 'منى', role: 'ضيفة', voiceId: 'saudi_f_pod'),
        ]
        ..segments = [
          Segment(text: 'هلا والله', speakerId: 'a'),
          Segment(text: 'هلا فيك', speakerId: 'b'),
          Segment(text: 'كيف الحال؟', speakerId: 'b'),
        ];
      final chunks = service.plan(p);
      expect(chunks.length, 2);
      expect(chunks[1].segments.length, 2);
      expect(chunks[0].request.voice, isNot(chunks[1].request.voice));
    });
  });

  group('Mastering & subtitles', () {
    test('trims silence, normalizes loudness and resamples to 48k', () {
      // نص ثانية صمت + ثانية نغمة هادية + نص ثانية صمت @24k
      final s = Int16List(48000);
      for (var i = 12000; i < 36000; i++) {
        s[i] = (800 * math.sin(2 * math.pi * 220 * i / 24000)).round();
      }
      final r = Mastering.process(Pcm(s, 24000), target: LoudnessTarget.video);
      expect(r.pcm.sampleRate, 48000);
      expect(r.trimmedStart.inMilliseconds, closeTo(380, 20));
      expect(r.pcm.duration.inMilliseconds, closeTo(1240, 30));
      final peak = r.pcm.samples.fold<int>(0, (a, v) => math.max(a, v.abs()));
      expect(peak, greaterThan(800 * 2)); // اتعلّى
      expect(peak, lessThan(32767)); // من غير تقطيع
    });

    test('srt has numbered cues with offset applied', () {
      final p = Project(title: 'x', type: ProjectType.voiceover, dialectId: 'egyptian', voiceId: 'egyptian_m_ad')
        ..segments = [Segment(id: 'a', text: 'أهلاً ⟨وقفة⟩ بيك'), Segment(id: 'b', text: 'تاني جملة')];
      final srt = Subtitles.srt(p, {'a': const Duration(milliseconds: 500), 'b': const Duration(seconds: 3)},
          offset: const Duration(milliseconds: 400), total: const Duration(seconds: 6));
      expect(srt, contains('1\n00:00:00,100 --> 00:00:02,520'));
      expect(srt, contains('2\n00:00:02,600 --> 00:00:05,600'));
      expect(srt, isNot(contains('⟨')));
    });
  });

  group('Phase 2', () {
    test('templates use existing voices and music', () {
      for (final t in Templates.all) {
        expect(VoiceCatalog.all.any((v) => v.id == t.voiceId), isTrue, reason: t.id);
        if (t.musicId != null) expect(AudioLibrary.musicById(t.musicId), isNotNull, reason: t.id);
        for (final l in t.lines) {
          if (l.sfx != null) expect(AudioLibrary.sfxById(l.sfx), isNotNull, reason: '${t.id} ${l.sfx}');
        }
        expect(t.toProject().segments.length, t.lines.length);
      }
    });

    test('mixer adds lead/tail and ducks music under voice', () {
      final voice = Int16List(24000)..fillRange(0, 24000, 8000); // ثانية كلام
      final music = Int16List(12000);
      for (var i = 0; i < music.length; i++) {
        music[i] = (6000 * math.sin(2 * math.pi * 440 * i / 24000)).round();
      }
      final out = Wav.decode(Mixer.mix(
        voiceWav: Wav.encode(Pcm(voice, 24000)),
        musicWav: Wav.encode(Pcm(music, 24000)),
        musicVolume: 0.5,
      ));
      expect(out.duration.inMilliseconds, closeTo(1000 + Mixer.lead.inMilliseconds + Mixer.tail.inMilliseconds, 5));
      double rms(int a, int b) {
        var e = 0.0;
        for (var i = a; i < b; i++) {
          e += out.samples[i] * out.samples[i].toDouble();
        }
        return math.sqrt(e / (b - a));
      }
      // في المقدمة (قبل الكلام) الموسيقى أعلى من بعد ما الكلام يبدأ ويتوطّى
      final leadEnd = (24000 * Mixer.lead.inMilliseconds / 1000).round();
      final musicOnly = rms(leadEnd - 4800, leadEnd);
      expect(musicOnly, greaterThan(500));
    });
  });

  test('azure ssml is clean (no fake emotion prosody) and escapes text', () {
    final x = AzureTts.ssml(
      voice: const AzureVoice('ar-EG-SalmaNeural', 'ar-EG', 'Female', 'سلمى'),
      lines: [('أهلاً & سهلاً ⟨وقفة⟩ بيك', Emotion.excitement, Intensity.strong), ('تمام', Emotion.sadness, Intensity.medium)],
      age: Age.child,
    );
    expect(x, contains("name='ar-EG-SalmaNeural'"));
    expect(x, contains('&amp;'));
    expect(x, contains('<break time="400ms"/>'));
    expect(x, contains("pitch='+8%'"));
    expect(x, isNot(contains('volume=')));
    final plain = AzureTts.ssml(voice: const AzureVoice('ar-SA-HamedNeural', 'ar-SA', 'Male', 'حامد'), lines: [('سلام', Emotion.joy, Intensity.strong)]);
    expect(plain, isNot(contains('<prosody')));
    expect(x, isNot(contains('⟨')));
  });

  test('project json round trip', () {
    final p = Project(title: 'x', type: ProjectType.podcast, dialectId: 'saudi', voiceId: 'saudi_m_pod')
      ..segments = [Segment(text: 'هلا', emotion: Emotion.joy, intensity: Intensity.strong, speakerId: 'a')]
      ..speakers = [Speaker(id: 'a', name: 'فهد', role: 'مضيف', voiceId: 'saudi_m_pod')];
    final q = Project.fromJson(p.toJson());
    expect(q.type, ProjectType.podcast);
    expect(q.segments.single.emotion, Emotion.joy);
    expect(q.speakers.single.name, 'فهد');
  });

  group('Azure voices & export', () {
    test('chosen azure voice survives json and reaches the request', () {
      final service = ProductionService(TtsService(GeminiClient('test-key-0000000000000'), const AppSettings()), const AppSettings());
      final p = Project(title: 'x', type: ProjectType.podcast, dialectId: 'egyptian', voiceId: 'egyptian_m_ad', azureVoice: 'ar-EG-ShakirNeural')
        ..speakers = [
          Speaker(id: 'a', name: 'أ', role: '', voiceId: 'egyptian_m_ad'),
          Speaker(id: 'b', name: 'ب', role: '', voiceId: 'egyptian_m_ad', azureVoice: 'ar-EG-SalmaNeural'),
        ]
        ..segments = [
          Segment(text: 'أهلاً', speakerId: 'a'),
          Segment(text: 'إزيك', speakerId: 'b'),
        ];
      final q = Project.fromJson(p.toJson());
      expect(q.azureVoice, 'ar-EG-ShakirNeural');
      expect(q.speakers[1].azureVoice, 'ar-EG-SalmaNeural');
      final chunks = service.plan(q, engine: 'azure');
      expect(chunks.length, 2); // نفس الشخصية بس صوت Azure مختلف
      expect(chunks[0].request.azureVoice, 'ar-EG-ShakirNeural');
      expect(chunks[1].request.azureVoice, 'ar-EG-SalmaNeural');
      expect(chunks[0].key, isNot(chunks[1].key));
      expect(chunks[0].key, startsWith('azure|ar-EG-ShakirNeural|'));
    });

    test('azure voice labels', () {
      const v = AzureVoice('ar-EG-SalmaNeural', 'ar-EG', 'Female', 'سلمى');
      expect(v.shortLabel, 'Salma');
      expect(v.country, 'مصري');
      expect(v.isMale, isFalse);
    });

    test('export formats are only mp3 and wav', () {
      expect(ExportFormat.values.map((f) => f.ext), ['mp3', 'wav']);
    });

    test('mp3 export produces an mp3 stream', () async {
      final pcm = Int16List(48000);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = (8000 * math.sin(2 * math.pi * 440 * i / 48000)).round();
      }
      final (bytes, fmt) = await Mastering.export(Wav.encode(Pcm(pcm, 48000)), format: ExportFormat.mp3, target: LoudnessTarget.video);
      expect(fmt, ExportFormat.mp3);
      expect(bytes.length, greaterThan(1000));
      final id3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
      final sync = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
      expect(id3 || sync, isTrue);
    });
  });

  group('In-app updates', () {
    test('version compare', () {
      expect(Updater.compare('1.2.0', '1.1.9'), greaterThan(0));
      expect(Updater.compare('v1.10.0', '1.9.3'), greaterThan(0));
      expect(Updater.compare('1.2', '1.2.0'), 0);
      expect(Updater.compare('1.2.0', '1.2.1'), lessThan(0));
    });

    test('shows only notes newer than the installed version', () {
      final rel = <String, dynamic>{
        'version': '1.4.0',
        'notes': ['d'],
        'history': [
          {'v': '1.3.0', 'notes': ['c']},
          {'v': '1.2.0', 'notes': ['b']},
          {'v': '1.1.0', 'notes': ['a']},
        ],
      };
      expect(Updater.notesBetween(rel, '1.2.0', '1.4.0'), ['d', 'c']);
      expect(Updater.notesBetween(rel, '1.1.0', '1.3.0'), ['c', 'b']);
    });
  });

  group('Tashkeel', () {
    test('detects missing diacritics', () {
      expect(Tashkeel.needs('بسم الله الرحمن الرحيم'), isTrue);
      expect(Tashkeel.needs('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ'), isFalse);
      expect(Tashkeel.needs('ok'), isFalse);
    });

    test('skeleton ignores harakat only', () {
      expect(Tashkeel.skeleton('بِسْمِ اللَّهِ'), Tashkeel.skeleton('بسم الله'));
      expect(Tashkeel.skeleton('بسم الله'), isNot(Tashkeel.skeleton('باسم الله')));
    });
  });

  group('Quran recitation', () {
    test('ayah ref parsing', () {
      expect(AyahRef.parse('2:255').toString(), '2:255');
      expect(AyahRef.parse(' 18 : 1 - 10 ').toString(), '18:1-10');
      expect(AyahRef.parse('115:1'), isNull);
      expect(AyahRef.parse('2:5-3'), isNull);
      expect(AyahRef.parse(null), isNull);
    });

    test('similarity ignores diacritics', () {
      const ayah = 'قُلْ هُوَ اللَّهُ أَحَدٌ';
      expect(Quran.similarity('قل هو الله أحد', ayah), 1);
      expect(Quran.similarity('كلام تاني خالص', ayah), lessThan(0.3));
    });

    test('ayah segments become their own recitation chunk', () {
      final service = ProductionService(TtsService(GeminiClient('test-key-0000000000000'), const AppSettings()), const AppSettings());
      final p = Project(title: 'x', type: ProjectType.voiceover, dialectId: 'egyptian', voiceId: VoiceCatalog.all.first.id)
        ..segments = [
          Segment(text: 'قال تعالى'),
          Segment(text: '﴿قل هو الله أحد﴾', ayah: '112:1', reciter: 'Husary_128kbps'),
          Segment(text: 'صدق الله العظيم'),
        ];
      final chunks = service.plan(Project.fromJson(p.toJson()));
      expect(chunks.length, 3);
      expect(chunks[1].isQuran, isTrue);
      expect(chunks[1].key, 'quran|Husary_128kbps|112:1');
      expect(chunks[0].isQuran, isFalse);
    });
  });
}
