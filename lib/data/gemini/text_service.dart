import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/dialects.dart';
import '../catalog/emotions.dart';
import 'gemini_client.dart';

class EmotionLine {
  const EmotionLine(this.text, this.emotion, this.intensity);
  final String text;
  final Emotion emotion;
  final Intensity intensity;
}

class PodcastSpeakerDraft {
  const PodcastSpeakerDraft({required this.id, required this.name, required this.role, required this.gender, required this.age});
  final String id;
  final String name;
  final String role;
  final Gender gender;
  final Age age;
}

class PodcastTurnDraft {
  const PodcastTurnDraft(this.speakerId, this.text, this.emotion);
  final String speakerId;
  final String text;
  final Emotion emotion;
}

class PodcastDraft {
  const PodcastDraft(this.speakers, this.turns);
  final List<PodcastSpeakerDraft> speakers;
  final List<PodcastTurnDraft> turns;
}

/// مهام النص بالذكاء الاصطناعي: تحويل اللهجة، اكتشاف المشاعر، كتابة البودكاست، التفريغ.
class TextService {
  TextService(this.client);
  final GeminiClient client;

  static final _emotionNames = Emotion.values.map((e) => e.name).toList();

  Future<String> rewriteToDialect(String text, String dialectId) {
    final d = Dialects.byId(dialectId);
    return client.generateText(
      text,
      system: 'أنت محرر نصوص صوتية محترف. حوّل النص اللي هيوصلك إلى ${d.rewriteGuide} '
          'حافظ على المعنى بالظبط، وخلّي الجمل طبيعية للإلقاء الصوتي، وما تزودش أي شرح. '
          'سيب أي علامات بين ⟨ ⟩ زي ما هي. أخرج النص المعدّل فقط.',
      temperature: 0.5,
    );
  }

  /// يقسّم النص لجمل ويقترح إحساس مناسب لكل جملة.
  Future<List<EmotionLine>> detectEmotions(String text) async {
    final res = await client.generateJson(
      text,
      system: 'أنت مخرج أداء صوتي. قسّم النص لجمل منطقية للإلقاء (من غير ما تغيّر ولا كلمة)، '
          'واختار لكل جملة إحساس واحد من: ${_emotionNames.join(', ')}، وشدة من: light, medium, strong.',
      schema: {
        'type': 'OBJECT',
        'properties': {
          'lines': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'text': {'type': 'STRING'},
                'emotion': {'type': 'STRING', 'enum': _emotionNames},
                'intensity': {'type': 'STRING', 'enum': ['light', 'medium', 'strong']},
              },
              'required': ['text', 'emotion', 'intensity'],
            }
          }
        },
        'required': ['lines'],
      },
    );
    return [
      for (final l in (res['lines'] as List? ?? const []))
        if ((l['text'] as String? ?? '').trim().isNotEmpty)
          EmotionLine((l['text'] as String).trim(), Emotion.byName(l['emotion'] as String?), Intensity.byName(l['intensity'] as String?)),
    ];
  }

  Future<PodcastDraft> writePodcast({required String source, required String dialectId, required int speakers}) async {
    final d = Dialects.byId(dialectId);
    final res = await client.generateJson(
      source,
      system: 'أنت كاتب ومخرج بودكاست عربي محترف. حوّل المحتوى اللي هيوصلك لحوار بودكاست طبيعي وممتع '
          'بين $speakers متحدثين، مكتوب بـ ${d.rewriteGuide} '
          'ابدأ بترحيب قصير واختم بخاتمة. خلي كل دور جملة أو جملتين. '
          'لكل دور اختار إحساس من: ${_emotionNames.join(', ')}. '
          'لكل متحدث حدد: id قصير بالإنجليزي، اسم عربي، دوره، النوع (male/female)، والعمر (child/young/adult/elder).',
      schema: {
        'type': 'OBJECT',
        'properties': {
          'speakers': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'id': {'type': 'STRING'},
                'name': {'type': 'STRING'},
                'role': {'type': 'STRING'},
                'gender': {'type': 'STRING', 'enum': ['male', 'female']},
                'age': {'type': 'STRING', 'enum': ['child', 'young', 'adult', 'elder']},
              },
              'required': ['id', 'name', 'role', 'gender', 'age'],
            }
          },
          'turns': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'speakerId': {'type': 'STRING'},
                'text': {'type': 'STRING'},
                'emotion': {'type': 'STRING', 'enum': _emotionNames},
              },
              'required': ['speakerId', 'text', 'emotion'],
            }
          },
        },
        'required': ['speakers', 'turns'],
      },
    );
    final sp = [
      for (final s in (res['speakers'] as List? ?? const []))
        PodcastSpeakerDraft(
          id: s['id'].toString(),
          name: s['name'].toString(),
          role: s['role'].toString(),
          gender: Gender.byName(s['gender'] as String?),
          age: Age.byName(s['age'] as String?),
        ),
    ];
    final ids = sp.map((s) => s.id).toSet();
    final turns = [
      for (final t in (res['turns'] as List? ?? const []))
        if (ids.contains(t['speakerId']) && (t['text'] as String? ?? '').trim().isNotEmpty)
          PodcastTurnDraft(t['speakerId'].toString(), (t['text'] as String).trim(), Emotion.byName(t['emotion'] as String?)),
    ];
    return PodcastDraft(sp, turns);
  }

  Future<String> transcribe(Uint8List bytes, String mime, {bool timestamps = false}) {
    return client.generateText(
      'فرّغ الملف الصوتي ده حرفياً.',
      system: 'أنت خبير تفريغ صوتي. اكتب الكلام كما نُطق حرفياً بلهجته الأصلية، من غير تلخيص ولا تصحيح ولا حذف. '
          '${timestamps ? 'ابدأ كل فقرة بطابع زمني بالشكل [MM:SS].' : 'من غير طوابع زمنية.'} '
          'أخرج النص فقط.',
      inlineParts: [GeminiClient.inlineData(bytes, mime)],
      temperature: 0.1,
    );
  }
}

final textServiceProvider = Provider<TextService?>((ref) {
  final c = ref.watch(geminiClientProvider);
  return c == null ? null : TextService(c);
});
