import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'gift_widgets.dart';
import 'ui.dart';

/// Полноэкранное появление подарка.
///
/// Сценарий зависит от редкости:
/// * обычный — подарок мягко выезжает снизу, лёгкое конфетти;
/// * редкий — свет собирается в шар, вспышка, одна волна, конфетти;
/// * эпический — то же + вращающиеся лучи и две волны;
/// * легендарный — золотые лучи, три золотые волны, золотая вспышка, блеск на названии.
///
/// Все «вечные» эффекты (лучи, пылинки, парение) зациклены без швов: за один круг
/// каждая величина возвращается ровно в начальное значение. Салют — одноразовый
/// и полностью гаснет, а не начинается заново.
///
/// [ug] — подарок в формате сервера: {gift:{…}, from, text, serial, supply, unique}
/// или просто описание подарка из каталога (тогда передай его в [ug]['gift']).
Future<void> showGiftReveal(BuildContext context, Map<String, dynamic> ug,
    {String? title, String? subtitle, String button = 'Класс!'}) async {
  HapticFeedback.lightImpact();
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'gift',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, _, __) =>
        _Reveal(ug: ug, title: title, subtitle: subtitle, button: button),
    transitionBuilder: (ctx, a, _, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
  );
}

class _Reveal extends StatefulWidget {
  final Map<String, dynamic> ug;
  final String? title;
  final String? subtitle;
  final String button;
  const _Reveal({required this.ug, this.title, this.subtitle, required this.button});
  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with TickerProviderStateMixin {
  static const _introMs = 2400;
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: _introMs));
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));
  late final List<_Spark> _burst;
  late final List<_Mote> _motes;
  late final List<_Mote> _charge;
  bool _buzzed = false;

  Map<String, dynamic> get _gift =>
      (widget.ug['gift'] as Map?)?.cast<String, dynamic>() ?? widget.ug;
  Map<String, dynamic>? get _unique => (widget.ug['unique'] as Map?)?.cast<String, dynamic>();
  String get _rarity => _gift['rarity'] as String? ?? 'common';
  bool get _legend => _rarity == 'legendary';
  bool get _common => _rarity == 'common' && _unique == null;

  /// Уровень «пышности»: 0 обычный, 1 редкий, 2 эпический, 3 легендарный/уникальный.
  int get _lvl {
    if (_unique != null) return 3;
    return switch (_rarity) { 'legendary' => 3, 'epic' => 2, 'rare' => 1, _ => 0 };
  }

  /// Момент «появления» подарка (доля интро).
  double get _popAt => _common ? 0.04 : 0.24;

  List<Color> get _palette {
    final u = _unique;
    if (u != null) {
      final cs = ((u['backdrop'] as Map?)?['colors'] as List?)
          ?.map((e) => hexColor(e as String))
          .toList();
      if (cs != null && cs.length >= 2) return [cs[0], cs[1], Colors.white, cs[0]];
    }
    return switch (_rarity) {
      'legendary' => const [Color(0xFFFFD166), Color(0xFFFFB020), Color(0xFFFFF4C8), Color(0xFFFF9A3D)],
      'epic' => const [Color(0xFFB57BFF), Color(0xFF6A5BFF), Color(0xFFFF7AB6), Color(0xFF7DD3FC)],
      'rare' => const [Color(0xFF5B9DFF), Color(0xFF34D399), Color(0xFFA5B4FC), Color(0xFFFDE68A)],
      _ => [appState.accent, const Color(0xFFFF8FC0), const Color(0xFFFFD166), const Color(0xFF7DD3FC)],
    };
  }

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    final pal = _palette;
    final lvl = _lvl;
    // одноразовый салют
    final n = [34, 56, 72, 96][lvl];
    _burst = List.generate(n, (i) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final speed = 220 + rnd.nextDouble() * (260 + 120 * lvl);
      return _Spark(
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed - 120,
        color: pal[rnd.nextInt(pal.length)],
        size: 2.5 + rnd.nextDouble() * 5,
        spin: (rnd.nextDouble() - 0.5) * 10,
        star: rnd.nextDouble() < (lvl >= 2 ? 0.45 : 0.25),
        life: 1.1 + rnd.nextDouble() * 0.7,
      );
    });
    // пылинки, которые всё время плавают вокруг (бесшовный цикл)
    final m = [8, 16, 24, 34][lvl];
    _motes = List.generate(
        m,
        (i) => _Mote(
              x: rnd.nextDouble() * 2 - 1,
              phase: rnd.nextDouble(),
              speed: 1 + rnd.nextInt(2), // целое число — цикл без рывка
              size: 1.2 + rnd.nextDouble() * 2.6,
              sway: rnd.nextDouble() * 2 * math.pi,
              color: pal[rnd.nextInt(pal.length)],
            ));
    // свет, который собирается в шар перед вспышкой
    _charge = List.generate(
        lvl == 0 ? 0 : 18 + lvl * 8,
        (i) => _Mote(
              x: rnd.nextDouble() * 2 * math.pi,
              phase: rnd.nextDouble() * 0.35,
              speed: 1,
              size: 1.5 + rnd.nextDouble() * 2.5,
              sway: 0.6 + rnd.nextDouble() * 0.5,
              color: pal[rnd.nextInt(pal.length)],
            ));
    _intro.addListener(() {
      if (!_buzzed && _intro.value >= _popAt) {
        _buzzed = true;
        HapticFeedback.heavyImpact();
        if (_legend) {
          Future.delayed(const Duration(milliseconds: 160), HapticFeedback.heavyImpact);
        }
      }
    });
    if (appState.motion) {
      _intro.forward();
      _loop.repeat();
    } else {
      _intro.value = 1;
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final g = _gift;
    final from = (widget.ug['from'] as Map?)?.cast<String, dynamic>();
    final text = (widget.ug['text'] as String? ?? '').trim();
    final serial = widget.ug['serial'];
    final u = _unique;
    final pal = _palette;
    final lvl = _lvl;
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final artSize = math.min(size.width * 0.5, 210.0);
    final center = Offset(size.width / 2, size.height * 0.36);
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _loop]),
      builder: (context, _) {
        final t = _intro.value;
        final loop = _loop.value; // 0..1, бесшовно
        final bg = Curves.easeOut.transform(_seg(t, 0, 0.16));
        final popT = _seg(t, _popAt, _popAt + 0.26);
        final pop = Curves.easeOutBack.transform(popT);
        final after = Curves.easeOut.transform(_seg(t, _popAt, _popAt + 0.35));
        final flash = lvl == 0 ? 0.0 : (1 - _seg(t, _popAt, _popAt + 0.14)) * (t >= _popAt ? 1 : 0);
        final breathe = math.sin(loop * 2 * math.pi * 2); // 2 вдоха за круг
        final float = math.sin(loop * 2 * math.pi * 2) * 7;
        final tilt = math.sin(loop * 2 * math.pi) * (lvl >= 2 ? 0.05 : 0.03);
        double reveal(double a) => Curves.easeOutCubic.transform(_seg(t, a, a + 0.18));
        final burstSec = (t - _popAt) * _introMs / 1000;
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // размытие + цветная атмосфера редкости
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18 * bg, sigmaY: 18 * bg),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, (center.dy / size.height) * 2 - 1),
                        radius: 1.05,
                        colors: [
                          Color.lerp(pal[0], Colors.black, 0.45)!.withValues(alpha: 0.82 * bg),
                          Colors.black.withValues(alpha: 0.9 * bg),
                        ],
                      ),
                    ),
                  ),
                ),
                // лучи, ореол, волны, пылинки, салют
                IgnorePointer(
                  child: CustomPaint(
                    painter: _StagePainter(
                      center: center,
                      art: artSize,
                      lvl: lvl,
                      pal: pal,
                      loop: loop,
                      open: after,
                      breathe: breathe,
                      intro: t,
                      popAt: _popAt,
                      burstSec: burstSec,
                      burst: _burst,
                      motes: _motes,
                      charge: _charge,
                    ),
                  ),
                ),
                // сам подарок
                Positioned(
                  left: 0,
                  right: 0,
                  top: center.dy - artSize / 2,
                  child: Center(
                    child: Opacity(
                      opacity: popT > 0 ? math.min(1.0, popT * 3) : 0,
                      child: Transform.translate(
                        offset: Offset(0, float * after + (_common ? 60 * (1 - pop) : 0)),
                        child: Transform.rotate(
                          angle: tilt * after + (1 - popT) * (_common ? 0 : -0.25),
                          child: Transform.scale(
                            scale: (_common ? 0.7 : 0.2) + (_common ? 0.3 : 0.8) * pop,
                            child: GiftArt(gift: g, unique: u, size: artSize),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // подписи
                Positioned(
                  left: 24,
                  right: 24,
                  top: center.dy + artSize / 2 + 26,
                  child: Column(
                    children: [
                      _in(
                        reveal(_popAt + 0.12),
                        Text(
                          widget.title ?? (u != null ? 'Уникальный подарок!' : 'Вам подарок!'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _in(
                        reveal(_popAt + 0.18),
                        _Shiny(
                          enabled: lvl >= 3,
                          t: loop,
                          child: Text(
                            '${g['title'] ?? 'Подарок'}${u != null && u['no'] != null ? ' #${u['no']}' : ''}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _in(
                        reveal(_popAt + 0.24),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _chip(rarityName(_rarity), rarityColor(_rarity)),
                            if (serial != null)
                              _chip(
                                  '№$serial${widget.ug['supply'] != null ? ' из ${widget.ug['supply']}' : ''}',
                                  const Color(0xFF64748B)),
                            if (u != null) ...[
                              _chip('Фон: ${u['backdrop']?['name']} · ${u['backdrop']?['pct']}%',
                                  hexColor((u['backdrop']?['colors'] as List?)?.first as String? ??
                                      '#6366F1')),
                              _chip(
                                  'Узор: ${u['pattern']?['symbol']} ${u['pattern']?['name']} · ${u['pattern']?['pct']}%',
                                  const Color(0xFF8B5CF6)),
                            ],
                          ],
                        ),
                      ),
                      if (widget.subtitle != null || from != null || text.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _in(
                          reveal(_popAt + 0.3),
                          _NoteCard(
                            from: widget.subtitle ??
                                (from != null
                                    ? 'от ${from['display_name']}${widget.ug['anonymous'] == true ? ' · анонимно' : ''}'
                                    : null),
                            text: text,
                            accent: pal[0],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // кнопка
                Positioned(
                  left: 40,
                  right: 40,
                  bottom: mq.padding.bottom + 28,
                  child: _in(
                    reveal(_popAt + 0.36),
                    PrimaryButton(
                      label: widget.button,
                      gradient: LinearGradient(colors: [pal[0], pal[1]]),
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                // вспышка в момент появления
                if (flash > 0)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, (center.dy / size.height) * 2 - 1),
                          radius: 0.35 + 0.9 * (1 - flash),
                          colors: [
                            (_legend ? const Color(0xFFFFF4C2) : Colors.white)
                                .withValues(alpha: 0.85 * flash),
                            (_legend ? const Color(0xFFFFF4C2) : Colors.white).withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _in(double k, Widget child) => Opacity(
        opacity: k,
        child: Transform.translate(offset: Offset(0, 18 * (1 - k)), child: child),
      );

  Widget _chip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.7)),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
      );
}

/// Карточка «от кого» + текст к подарку, на стекле.
class _NoteCard extends StatelessWidget {
  final String? from;
  final String text;
  final Color accent;
  const _NoteCard({required this.from, required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              if (from != null)
                Text(from!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              if (text.isNotEmpty) ...[
                if (from != null) const SizedBox(height: 6),
                Text('«$text»',
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontStyle: FontStyle.italic,
                        fontSize: 15.5,
                        height: 1.35)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Переливающийся блик по тексту (легендарные и уникальные). Бесшовный цикл.
class _Shiny extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final double t;
  const _Shiny({required this.child, required this.enabled, required this.t});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    // блик проходит за первые 40% круга, дальше пауза — начало и конец совпадают
    final k = (t * 2 % 1.0);
    final x = k < 0.5 ? -1.6 + (k / 0.5) * 3.2 : 1.6;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment(x - 0.6, 0),
        end: Alignment(x + 0.6, 0),
        colors: const [Color(0xFFFFD166), Color(0xFFFFFFFF), Color(0xFFFFD166)],
        stops: const [0.2, 0.5, 0.8],
        tileMode: TileMode.clamp,
      ).createShader(r),
      child: child,
    );
  }
}

class _Spark {
  final double vx, vy, size, spin, life;
  final Color color;
  final bool star;
  _Spark({
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    required this.spin,
    required this.star,
    required this.life,
  });
}

class _Mote {
  final double x, phase, size, sway;
  final int speed;
  final Color color;
  _Mote({
    required this.x,
    required this.phase,
    required this.speed,
    required this.size,
    required this.sway,
    required this.color,
  });
}

void _star(Canvas canvas, Offset c, double r, Paint p) {
  canvas.drawPath(
    Path()
      ..moveTo(c.dx, c.dy - r * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r * 2)
      ..close(),
    p,
  );
}

/// Всё, что вокруг подарка: заряд света, лучи, ореол, волны, пылинки, салют.
class _StagePainter extends CustomPainter {
  final Offset center;
  final double art, loop, open, breathe, intro, popAt, burstSec;
  final int lvl;
  final List<Color> pal;
  final List<_Spark> burst;
  final List<_Mote> motes, charge;
  _StagePainter({
    required this.center,
    required this.art,
    required this.lvl,
    required this.pal,
    required this.loop,
    required this.open,
    required this.breathe,
    required this.intro,
    required this.popAt,
    required this.burstSec,
    required this.burst,
    required this.motes,
    required this.charge,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tone = pal[0];

    // 1) заряд: свет стягивается в центр и собирается в шар (до момента появления)
    if (charge.isNotEmpty && intro < popAt) {
      final k = intro / popAt; // 0..1
      final orb = Curves.easeIn.transform(k);
      for (final m in charge) {
        final kk = ((k - m.phase) / (1 - m.phase)).clamp(0.0, 1.0);
        if (kk <= 0) continue;
        final d = art * (1.3 * m.sway) * (1 - Curves.easeIn.transform(kk));
        final a = m.x + kk * 1.2;
        final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
        canvas.drawCircle(p, m.size, Paint()..color = m.color.withValues(alpha: 0.9 * math.sin(kk * math.pi)));
      }
      canvas.drawCircle(
        center,
        art * 0.12 * (0.3 + orb),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9 * orb)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 10 + 20 * orb),
      );
    }

    // 2) лучи (эпические и легендарные) — один полный оборот за круг: без швов
    if (lvl >= 2 && open > 0) {
      final r = size.longestSide * 0.7 * open;
      final n = lvl >= 3 ? 16 : 12;
      final rays = Paint()
        ..shader = RadialGradient(colors: [
          tone.withValues(alpha: (lvl >= 3 ? 0.34 : 0.22) * open),
          tone.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(loop * 2 * math.pi / n * 2); // сдвиг на 2 луча за круг — бесшовно
      for (var i = 0; i < n; i++) {
        final a = i * 2 * math.pi / n;
        final w = (lvl >= 3 ? 0.085 : 0.07) * (1 + 0.15 * math.sin(loop * 2 * math.pi * 2 + i));
        canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(math.cos(a - w) * r, math.sin(a - w) * r)
            ..lineTo(math.cos(a + w) * r, math.sin(a + w) * r)
            ..close(),
          rays,
        );
      }
      canvas.restore();
    }

    // 3) ореол за подарком, «дышит»
    if (open > 0) {
      final hr = art * (0.95 + 0.06 * breathe) * (0.6 + 0.4 * open);
      canvas.drawCircle(
        center,
        hr,
        Paint()
          ..shader = RadialGradient(colors: [
            tone.withValues(alpha: (0.35 + 0.12 * lvl) * open),
            tone.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: center, radius: hr)),
      );
    }

    // 4) ударные волны в момент появления: 1 / 2 / 3
    if (lvl >= 1) {
      final waves = lvl >= 3 ? 3 : lvl;
      final col = lvl >= 3 ? const Color(0xFFFFD166) : tone;
      for (var i = 0; i < waves; i++) {
        final start = popAt + i * 0.07;
        final k = ((intro - start) / 0.4).clamp(0.0, 1.0);
        if (k <= 0 || k >= 1) continue;
        final e = Curves.easeOutCubic.transform(k);
        canvas.drawCircle(
          center,
          art * 0.35 + e * size.longestSide * 0.55,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8 * (1 - k) + 1
            ..color = col.withValues(alpha: 0.65 * (1 - k)),
        );
      }
    }

    // 5) пылинки: поднимаются и плавно гаснут; целые скорости — цикл без рывков
    if (open > 0) {
      for (final m in motes) {
        final life = (loop * m.speed + m.phase) % 1.0;
        final a = math.sin(life * math.pi); // 0 в начале и в конце пути
        final x = center.dx + m.x * size.width * 0.48 +
            math.sin(life * 2 * math.pi + m.sway) * 12;
        final y = center.dy + art * 0.9 - life * size.height * 0.55;
        final p = Paint()..color = m.color.withValues(alpha: 0.75 * a * open);
        if (lvl >= 2 && m.size > 2.6) {
          _star(canvas, Offset(x, y), m.size * 0.8 * a + 0.3, p);
        } else {
          canvas.drawCircle(Offset(x, y), m.size * (0.6 + 0.4 * a), p);
        }
      }
    }

    // 6) салют — один раз, каждая искра полностью гаснет
    if (burstSec > 0) {
      for (final p in burst) {
        final tt = burstSec;
        if (tt >= p.life) continue;
        final drag = (1 - math.exp(-tt * 2.4)) / 2.4;
        final x = center.dx + p.vx * drag;
        final y = center.dy + p.vy * drag + 170 * tt * tt;
        final fade = 1 - Curves.easeIn.transform(tt / p.life);
        final paint = Paint()..color = p.color.withValues(alpha: fade);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(p.spin * tt);
        if (p.star) {
          _star(canvas, Offset.zero, p.size * 0.8, paint);
        } else {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset.zero, width: p.size * 1.6, height: p.size),
                  const Radius.circular(1.5)),
              paint);
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => true;
}
