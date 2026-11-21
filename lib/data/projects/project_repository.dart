import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../catalog/voices.dart';
import 'models.dart';

/// كل المشاريع، مرتبة من الأحدث.
class ProjectsNotifier extends Notifier<List<Project>> {
  @override
  List<Project> build() {
    final list = <Project>[];
    for (final v in LocalDb.projects.values) {
      try {
        list.add(Project.fromJson(jsonDecode(v as String) as Map));
      } catch (_) {
        // مشروع تالف: نتجاهله بدل ما التطبيق يقع
      }
    }
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Project? byId(String id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<Project> create(ProjectType type, {String? voiceId, String? title}) async {
    final voice = VoiceCatalog.byId(voiceId ?? 'egyptian_m_ad');
    final p = Project(
      title: title ?? '${type.label} جديد',
      type: type,
      dialectId: voice.dialectId,
      voiceId: voice.id,
    );
    await save(p);
    return p;
  }

  Future<void> save(Project p) async {
    p.updatedAt = DateTime.now();
    await LocalDb.projects.put(p.id, jsonEncode(p.toJson()));
    final others = state.where((e) => e.id != p.id).toList();
    state = [p.copy(), ...others];
  }

  Future<void> delete(String id) async {
    await LocalDb.projects.delete(id);
    state = state.where((e) => e.id != id).toList();
    await prune();
  }

  /// يمسح أي صوت متخزن مش مربوط بمشروع (بيوفّر مساحة).
  Future<int> prune() {
    final keep = <String>{};
    for (final p in state) {
      if (p.masterKey != null) keep.add(p.masterKey!);
      if (p.voiceKey != null) keep.add(p.voiceKey!);
      for (final s in p.segments) {
        if (s.audioKey != null) keep.add(s.audioKey!);
      }
    }
    return LocalDb.pruneAudio(keep);
  }
}

final projectsProvider = NotifierProvider<ProjectsNotifier, List<Project>>(ProjectsNotifier.new);
