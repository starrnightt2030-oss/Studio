import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/projects/project_repository.dart';
import '../../core/router.dart';
import '../../core/storage/key_store.dart';
import '../../core/theme/app_theme.dart';

/// الانترو: شعاع نور دهبي → المايك يظهر بتوهج وحلقة بتترسم → جزيئات نور تتجمع
/// → STUDIO حرف حرف → ELDAWLY تنزل بخبطة + لمعة → موجة صوت. ~3 ثواني، وبلمسة يتخطى.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF070B17);
  static const _gold = Color(0xFFF5B300);
  static const _total = Duration(milliseconds: 3200);

  late final AnimationController _c = AnimationController(vsync: this, duration: _total);
  final _player = AudioPlayer();
  final _particles = List.generate(70, (i) => _Particle(math.Random(i * 7919)));
  bool _impactDone = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_impactDone && _c.value >= 0.345) {
        _impactDone = true;
        HapticFeedback.heavyImpact();
      }
    });
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _leave();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _c.forward();
      try {
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.play(AssetSource('audio/intro.mp3'), volume: 0.9);
      } catch (_) {
        // الصوت اختياري: لو فشل (ويب من غير تفاعل مثلاً) نكمّل الأنيميشن عادي
      }
    });
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    _player.stop();
    if (ref.read(apiKeyProvider) == null) return context.go('/key');
    // نرجع لآخر حاجة كنت شغال عليها (والرجوع منها يوديك للرئيسية)
    final last = lastWorkRoute(ref.read(projectsProvider.notifier).byId);
    final router = GoRouter.of(context);
    router.go('/');
    if (last != null) WidgetsBinding.instance.addPostFrameCallback((_) => router.push(last));
  }

  @override
  void dispose() {
    _c.dispose();
    _player.dispose();
    super.dispose();
  }

  /// قيمة من 0 لـ 1 جوه فترة [a, b] من الأنيميشن.
  double _seg(double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _leave,
        child: Scaffold(
          backgroundColor: _bg,
          body: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final size = MediaQuery.of(context).size;
              final micSize = math.min(size.width * 0.52, 240.0);
              final fadeOut = 1 - _seg(0.9, 1.0, Curves.easeIn);
              final reveal = _seg(0.08, 0.42, Curves.easeOutCubic);
              final ring = _seg(0.14, 0.4, Curves.easeInOut);
              final glow = _seg(0.3, 0.5) * (1 - _seg(0.75, 1.0) * 0.4);
              final drop = _seg(0.345, 0.47, Curves.elasticOut);
              final dropIn = _seg(0.33, 0.36);
              final shine = _seg(0.42, 0.78, Curves.easeInOut);

              return Opacity(
                opacity: fadeOut,
                child: Stack(fit: StackFit.expand, children: [
                  // شعاع النور اللي بيعدّي في الأول
                  CustomPaint(painter: _SweepPainter(_seg(0.0, 0.34, Curves.easeInOutCubic))),
                  // الجزيئات اللي بتتجمع ناحية الاسم
                  CustomPaint(painter: _ParticlesPainter(_particles, _seg(0.2, 0.46, Curves.easeInCubic), _seg(0.46, 0.7))),
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: micSize + 28,
                        height: micSize + 28,
                        child: Stack(alignment: Alignment.center, children: [
                          CustomPaint(size: Size.square(micSize + 28), painter: _RingPainter(ring, glow)),
                          Opacity(
                            opacity: reveal,
                            child: Transform.scale(
                              scale: 0.72 + 0.28 * reveal,
                              child: Container(
                                width: micSize,
                                height: micSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: _gold.withValues(alpha: 0.35 * glow), blurRadius: 60 * glow + 1, spreadRadius: 4 * glow),
                                  ],
                                ),
                                child: ClipOval(child: Image.asset('assets/images/mic.jpg', fit: BoxFit.cover)),
                              ),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      _studioWord(),
                      const SizedBox(height: 4),
                      Opacity(
                        opacity: dropIn,
                        child: Transform.translate(
                          offset: Offset(0, -40 * (1 - drop)),
                          child: Transform.scale(
                            scale: 1.35 - 0.35 * drop,
                            child: ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (r) => LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: const [_gold, Color(0xFFFFF4C2), _gold],
                                stops: [
                                  (shine * 1.4 - 0.4).clamp(0.0, 1.0),
                                  (shine * 1.4 - 0.2).clamp(0.0, 1.0),
                                  (shine * 1.4).clamp(0.0, 1.0),
                                ],
                              ).createShader(r),
                              child: Text(
                                'ELDAWLY',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontFamily: Fonts.poster,
                                  fontSize: math.min(size.width * 0.2, 96),
                                  height: 0.95,
                                  letterSpacing: 2,
                                  color: _gold,
                                  shadows: const [Shadow(color: Color(0xFF8A5E00), offset: Offset(0, 4))],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(width: 180, height: 34, child: CustomPaint(painter: _WaveBarsPainter(_c.value, _seg(0.42, 0.55)))),
                    ]),
                  ),
                  Positioned(
                    bottom: 34,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: _seg(0.55, 0.7) * 0.7,
                      child: const Text('استوديو الصوت العربي',
                          textAlign: TextAlign.center, style: TextStyle(fontFamily: Fonts.display, color: Colors.white70, fontSize: 13)),
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }

  /// STUDIO: كل حرف بييجي من اتجاه مختلف ويتجمعوا.
  Widget _studioWord() {
    const word = 'STUDIO';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36 * _seg(0.36, 0.5, Curves.easeOut), height: 2, color: _gold),
        const SizedBox(width: 12),
        for (var i = 0; i < word.length; i++)
          Builder(builder: (_) {
            final p = _seg(0.24 + i * 0.025, 0.4 + i * 0.025, Curves.easeOutBack);
            final ang = (i * 1.7) % (2 * math.pi);
            return Opacity(
              opacity: p.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(math.cos(ang) * 60 * (1 - p), math.sin(ang) * 60 * (1 - p)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(word[i],
                      style: const TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w600, fontSize: 18, color: Color(0xFFE6EAF2))),
                ),
              ),
            );
          }),
        const SizedBox(width: 12),
        Container(width: 36 * _seg(0.36, 0.5, Curves.easeOut), height: 2, color: _gold),
      ]),
    );
  }
}

class _Particle {
  _Particle(math.Random r)
      : angle = r.nextDouble() * 2 * math.pi,
        dist = 0.45 + r.nextDouble() * 0.6,
        size = 1 + r.nextDouble() * 2.6,
        blue = r.nextDouble() < 0.3,
        drift = r.nextDouble();
  final double angle;
  final double dist;
  final double size;
  final bool blue;
  final double drift;
}

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter(this.ps, this.gather, this.scatter);
  final List<_Particle> ps;
  final double gather;
  final double scatter;

  @override
  void paint(Canvas canvas, Size size) {
    if (gather <= 0) return;
    final center = Offset(size.width / 2, size.height / 2 + size.width * 0.28);
    final maxR = size.longestSide * 0.6;
    for (final p in ps) {
      final r = maxR * p.dist * (1 - gather) + scatter * 40 * p.drift;
      final a = p.angle + gather * 1.2;
      final pos = center + Offset(math.cos(a) * r, math.sin(a) * r * 0.7);
      final alpha = (gather < 0.15 ? gather / 0.15 : 1.0) * (1 - scatter);
      final c = (p.blue ? const Color(0xFF3B6EF5) : const Color(0xFFF5B300)).withValues(alpha: alpha * 0.85);
      canvas.drawCircle(pos, p.size, Paint()..color = c);
      canvas.drawCircle(pos, p.size * 3, Paint()..color = c.withValues(alpha: alpha * 0.12));
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter o) => o.gather != gather || o.scatter != scatter;
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final x = -size.width * 0.6 + t * size.width * 2.2;
    final rect = Rect.fromLTWH(x - size.width * 0.35, 0, size.width * 0.7, size.height);
    final shader = const LinearGradient(
      colors: [Color(0x00F5B300), Color(0x33F5B300), Color(0x66FFE7A0), Color(0x33F5B300), Color(0x00F5B300)],
    ).createShader(rect);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.35);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawRect(rect.inflate(size.height), Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SweepPainter o) => o.t != t;
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.glow);
  final double progress;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF5B300);
    canvas.drawArc(rect.deflate(4), -math.pi / 2, 2 * math.pi * progress, false, p);
    if (glow > 0) {
      canvas.drawArc(
        rect.deflate(4),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = const Color(0xFFF5B300).withValues(alpha: 0.18 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.progress != progress || o.glow != glow;
}

class _WaveBarsPainter extends CustomPainter {
  _WaveBarsPainter(this.t, this.appear);
  final double t;
  final double appear;

  @override
  void paint(Canvas canvas, Size size) {
    if (appear <= 0) return;
    const n = 23;
    final bw = size.width / (n * 1.8);
    for (var i = 0; i < n; i++) {
      final mid = 1 - ((i - n / 2).abs() / (n / 2));
      final h = (0.2 + 0.8 * mid * (0.5 + 0.5 * math.sin(t * 40 + i * 0.9))) * size.height * appear;
      final x = i * bw * 1.8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, bw, h), Radius.circular(bw)),
        Paint()..color = Color.lerp(const Color(0xFF3B6EF5), const Color(0xFFF5B300), mid)!.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveBarsPainter o) => o.t != t || o.appear != appear;
}
