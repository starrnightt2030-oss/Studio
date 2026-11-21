import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:studio_eldawly/core/audio/wav.dart';
import 'package:studio_eldawly/core/audio/mastering.dart';
import 'package:studio_eldawly/core/audio/subtitles.dart';
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

  test('project json round trip', () {
    final p = Project(title: 'x', type: ProjectType.podcast, dialectId: 'saudi', voiceId: 'saudi_m_pod')
      ..segments = [Segment(text: 'هلا', emotion: Emotion.joy, intensity: Intensity.strong, speakerId: 'a')]
      ..speakers = [Speaker(id: 'a', name: 'فهد', role: 'مضيف', voiceId: 'saudi_m_pod')];
    final q = Project.fromJson(p.toJson());
    expect(q.type, ProjectType.podcast);
    expect(q.segments.single.emotion, Emotion.joy);
    expect(q.speakers.single.name, 'فهد');
  });
}
