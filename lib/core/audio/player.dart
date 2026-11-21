import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class StudioPlayerState {
  const StudioPlayerState({this.id, this.playing = false, this.position = Duration.zero, this.duration = Duration.zero});
  final String? id;
  final bool playing;
  final Duration position;
  final Duration duration;

  double get progress =>
      duration.inMilliseconds == 0 ? 0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  StudioPlayerState copyWith({String? id, bool? playing, Duration? position, Duration? duration}) => StudioPlayerState(
        id: id ?? this.id,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
      );
}

/// مشغّل واحد للتطبيق كله: تشغيل عينة، جملة، أو الملف النهائي.
class StudioPlayer extends Notifier<StudioPlayerState> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription>[];

  @override
  StudioPlayerState build() {
    _subs.addAll([
      _player.onPositionChanged.listen((p) => state = state.copyWith(position: p)),
      _player.onDurationChanged.listen((d) => state = state.copyWith(duration: d)),
      _player.onPlayerComplete.listen((_) => state = state.copyWith(playing: false, position: state.duration)),
    ]);
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _player.dispose();
    });
    return const StudioPlayerState();
  }

  Future<void> playBytes(String id, Uint8List wav) async {
    await _player.stop();
    state = StudioPlayerState(id: id, playing: true);
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  Future<void> toggle(String id, Uint8List wav) async {
    if (state.id == id && state.playing) {
      await _player.pause();
      state = state.copyWith(playing: false);
    } else if (state.id == id && !state.playing && state.position < state.duration && state.position > Duration.zero) {
      await _player.resume();
      state = state.copyWith(playing: true);
    } else {
      await playBytes(id, wav);
    }
  }

  Future<void> seek(Duration d) => _player.seek(d);

  Future<void> skip(int seconds) async {
    var t = state.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (state.duration > Duration.zero && t > state.duration) t = state.duration;
    await _player.seek(t);
  }

  Future<void> stop() async {
    await _player.stop();
    state = const StudioPlayerState();
  }
}

final playerProvider = NotifierProvider<StudioPlayer, StudioPlayerState>(StudioPlayer.new);
