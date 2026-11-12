import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Infinity Run – fast konstante Größen, Figur exakt auf Schienenmitte
class PixelRunnerScreen extends StatefulWidget {
  const PixelRunnerScreen({super.key});
  @override
  State<PixelRunnerScreen> createState() => _PixelRunnerScreenState();
}

class _PixelRunnerScreenState extends State<PixelRunnerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;
  final _rng = Random();

  int lane = 1;
  double laneX = 0.0;

  double speed = 6.0;
  double dist = 0;
  int score = 0;
  int coins = 0;
  int high = 0;
  bool dead = false;

  double jumpY = 0;
  double jumpV = 0;
  bool ducking = false;
  double duckT = 0;
  double runPhase = 0;

  bool jetpack = false;
  double jetpackT = 0;
  bool ghost = false;
  double ghostT = 0;

  double _panX = 0;
  double _panY = 0;
  bool _panUsed = false;

  final List<_Obs> obs = [];
  final List<_Coin> coinList = [];
  double spawnAcc = 0;
  double coinAcc = 0;
  double worldPhase = 0;

  static const double jumpPower = 14.0;
  static const double gravity = 21.0;
  static const double kPlayerZ = 3.0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      high = p.getInt('run_high') ?? 0;
      if (mounted) setState(() {});
    });
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_frame)..repeat();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  void _frame() {
    if (!mounted || dead) return;
    const dt = 1 / 60.0;

    final target = (lane - 1).toDouble();
    final d = target - laneX;
    if (d.abs() > 0.001) {
      laneX += d.clamp(-22 * dt, 22 * dt);
    } else {
      laneX = target;
    }

    dist += speed * dt;
    worldPhase += speed * dt * 0.1;
    score = dist.toInt() + coins * 5;
    speed = min(13.0, 6.0 + dist * 0.0012);

    final cadence =
        ducking ? 3.0 : (jumpY > 0.2 ? 2.0 : 10.0 + speed * 0.55);
    runPhase += dt * cadence;

    if (jumpY > 0 || jumpV > 0) {
      jumpV -= gravity * dt;
      jumpY += jumpV * dt;
      if (jumpY < 0) {
        jumpY = 0;
        jumpV = 0;
      }
    }
    if (ducking) {
      duckT -= dt;
      if (duckT <= 0) ducking = false;
    }
    if (jetpack) {
      jetpackT -= dt;
      if (jetpackT <= 0) jetpack = false;
    }
    if (ghost) {
      ghostT -= dt;
      if (ghostT <= 0) ghost = false;
    }

    spawnAcc += dt;
    if (spawnAcc > max(1.45, 2.2 - dist / 6000)) {
      spawnAcc = 0;
      final l = _rng.nextInt(3);
      final r = _rng.nextDouble();
      final kind = r < 0.45 ? 0 : (r < 0.72 ? 1 : 2);
      obs.add(_Obs(lane: l, z: 34, kind: kind, hue: _rng.nextDouble()));
    }

    coinAcc += dt;
    if (coinAcc > 0.48) {
      coinAcc = 0;
      coinList.add(
          _Coin(lane: _rng.nextInt(3), z: 34, high: _rng.nextDouble() < 0.18));
    }

    for (final o in obs) {
      o.z -= speed * dt;
    }
    obs.removeWhere((o) => o.z < 0.1);
    for (final c in coinList) {
      c.z -= speed * dt;
    }
    coinList.removeWhere((c) => c.z < 0.1);

    if (!ghost && !jetpack && (laneX - target).abs() < 0.12) {
      for (final o in obs) {
        if (o.lane != lane) continue;
        final dz = o.z - kPlayerZ;
        if (dz < 0.12 || dz > 1.05) continue;
        if (o.kind == 0 && jumpY < 0.85) {
          _die();
          return;
        }
        if (o.kind == 1 && !ducking) {
          _die();
          return;
        }
        if (o.kind == 2) {
          _die();
          return;
        }
      }
    }
    for (final c in coinList) {
      if (c.lane == lane && (c.z - kPlayerZ).abs() < 1.1) {
        if (c.high && jumpY < 0.25) continue;
        if (!c.high && ducking) continue;
        coins++;
        c.z = -10;
        HapticFeedback.lightImpact();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _die() async {
    if (dead) return;
    dead = true;
    HapticFeedback.heavyImpact();
    if (score > high) {
      high = score;
      final p = await SharedPreferences.getInstance();
      await p.setInt('run_high', high);
    }
    if (mounted) setState(() {});
  }

  void _restart() {
    if (!mounted) return;
    setState(() {
      lane = 1;
      laneX = 0;
      speed = 6.0;
      dist = 0;
      score = 0;
      coins = 0;
      dead = false;
      jumpY = 0;
      jumpV = 0;
      ducking = false;
      jetpack = false;
      ghost = false;
      obs.clear();
      coinList.clear();
      _panX = 0;
      _panY = 0;
      _panUsed = false;
    });
  }

  void _lane(int dir) {
    if (dead || !mounted) return;
    final n = (lane + dir).clamp(0, 2);
    if (n == lane) return;
    setState(() => lane = n);
    HapticFeedback.selectionClick();
  }

  void _jump() {
    if (dead || !mounted || ducking) return;
    if (jumpY > 0.05) return;
    setState(() => jumpV = jumpPower);
    HapticFeedback.mediumImpact();
  }

  void _duck() {
    if (dead || !mounted || jumpY > 0.28) return;
    setState(() {
      ducking = true;
      duckT = 1.4;
    });
    HapticFeedback.selectionClick();
  }

  void _jet() {
    if (dead || !mounted || jetpack) return;
    setState(() {
      jetpack = true;
      jetpackT = 7;
      jumpY = 2.4;
    });
  }

  void _ghost() {
    if (dead || !mounted || ghost) return;
    setState(() {
      ghost = true;
      ghostT = 5;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A9BC7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.home_rounded,
                        color: Colors.white70, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  _chip('$score', Icons.speed_rounded),
                  const SizedBox(width: 8),
                  _chip('$coins', Icons.monetization_on_rounded,
                      Colors.amberAccent),
                  const SizedBox(width: 8),
                  _chip('Spur ${lane + 1}', Icons.view_column_rounded,
                      Colors.lightGreenAccent),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  _panX = 0;
                  _panY = 0;
                  _panUsed = false;
                },
                onPanUpdate: (d) {
                  if (dead) return;
                  _panX += d.delta.dx;
                  _panY += d.delta.dy;
                  if (_panUsed) return;
                  if (_panX.abs() > 16 && _panX.abs() > _panY.abs()) {
                    _panUsed = true;
                    _lane(_panX < 0 ? -1 : 1);
                  } else if (_panY < -22 && _panY.abs() > _panX.abs()) {
                    _panUsed = true;
                    _jump();
                  } else if (_panY > 22 && _panY.abs() > _panX.abs()) {
                    _panUsed = true;
                    _duck();
                  }
                },
                onPanEnd: (d) {
                  if (dead || _panUsed) {
                    _panX = 0;
                    _panY = 0;
                    _panUsed = false;
                    return;
                  }
                  final vx = d.velocity.pixelsPerSecond.dx;
                  final vy = d.velocity.pixelsPerSecond.dy;
                  if (vx.abs() > 90 && vx.abs() > vy.abs()) {
                    _lane(vx < 0 ? -1 : 1);
                  } else if (vy < -70) {
                    _jump();
                  } else if (vy > 70) {
                    _duck();
                  }
                  _panX = 0;
                  _panY = 0;
                  _panUsed = false;
                },
                onTap: () {
                  if (!dead) _jump();
                },
                child: CustomPaint(
                  painter: _RunPainter(
                    laneX: laneX,
                    activeLane: lane,
                    obs: List.of(obs),
                    coins: List.of(coinList),
                    jumpY: jumpY,
                    ducking: ducking,
                    runPhase: runPhase,
                    worldPhase: worldPhase,
                    jetpack: jetpack,
                    ghost: ghost,
                    dead: dead,
                    speed: speed,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _btn(Icons.keyboard_arrow_up_rounded, _jump,
                          const Color(0xFFFFB300)),
                      const SizedBox(width: 10),
                      _btn(Icons.keyboard_arrow_down_rounded, _duck,
                          const Color(0xFFCE93D8)),
                      const SizedBox(width: 10),
                      _btn(Icons.rocket_launch_rounded, _jet,
                          const Color(0xFF00E5FF)),
                      const SizedBox(width: 10),
                      _btn(Icons.blur_on_rounded, _ghost,
                          const Color(0xFFE040FB)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _btn(Icons.chevron_left_rounded, () => _lane(-1),
                          Colors.white),
                      const SizedBox(width: 14),
                      Text(
                        '←  Spur ${lane + 1} / 3  →',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 14),
                      _btn(Icons.chevron_right_rounded, () => _lane(1),
                          Colors.white),
                    ],
                  ),
                  if (dead) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: _restart,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black26,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Play again'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String v, IconData icon, [Color c = Colors.white]) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.32),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 5),
            Text(v,
                style: TextStyle(
                    color: c, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );

  Widget _btn(IconData icon, VoidCallback on, Color c) => Material(
        color: Colors.black.withOpacity(0.36),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: on,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
              width: 54, height: 46, child: Icon(icon, color: c, size: 28)),
        ),
      );
}

class _Obs {
  int lane;
  double z;
  int kind;
  double hue;
  _Obs(
      {required this.lane,
      required this.z,
      required this.kind,
      this.hue = 0});
}

class _Coin {
  int lane;
  double z;
  bool high;
  _Coin({required this.lane, required this.z, this.high = false});
}

/// Sehr milde Perspektive – Objekte fast gleich groß nah und fern
class _Cam {
  final Size size;
  final double horizonY;
  final double groundY;
  static const double nearSpread = 0.24;

  _Cam(this.size)
      : horizonY = size.height * 0.34,
        groundY = size.height * 0.74;

  Offset project(double lx, double z, [double y = 0]) {
    final t = ((z - 1.0) / 33.0).clamp(0.0, 1.0);
    // Nur 30 % Verengung nach hinten
    final spread = nearSpread * (1.0 - t * 0.30);
    final sx = size.width * 0.5 + lx * size.width * spread;
    final sy =
        groundY + (horizonY - groundY) * t - y * (1.0 - t) * size.height * 0.09;
    return Offset(sx, sy);
  }

  /// Fast konstante Größe (max ~20 % Unterschied)
  double objectSize(double z, double base) {
    final t = ((z - 1.0) / 33.0).clamp(0.0, 1.0);
    return base * (1.0 - t * 0.20);
  }
}

class _RunPainter extends CustomPainter {
  final double laneX;
  final int activeLane;
  final List<_Obs> obs;
  final List<_Coin> coins;
  final double jumpY;
  final bool ducking;
  final double runPhase;
  final double worldPhase;
  final bool jetpack, ghost, dead;
  final double speed;

  static const double trackHalf = 0.11;
  static const double railGap = 0.052;

  _RunPainter({
    required this.laneX,
    required this.activeLane,
    required this.obs,
    required this.coins,
    required this.jumpY,
    required this.ducking,
    required this.runPhase,
    required this.worldPhase,
    required this.jetpack,
    required this.ghost,
    required this.dead,
    required this.speed,
  });

  Rect _r(double l, double t, double w, double h) =>
      Rect.fromLTWH(l, t, w.abs().clamp(0.5, 5000), h.abs().clamp(0.5, 5000));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 40 || size.height < 40) return;
    final cam = _Cam(size);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5BA8D0), Color(0xFF9BCFE8), Color(0xFFC8E0A0)],
          stops: [0, 0.4, 1],
        ).createShader(Offset.zero & size),
    );

    final sunC = Offset(size.width * 0.82, size.height * 0.1);
    canvas.drawCircle(
      sunC,
      size.width * 0.034,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFFFFFFB0), Color(0xFFFFC107)],
        ).createShader(_r(sunC.dx - 24, sunC.dy - 24, 48, 48)),
    );

    final skyShift = (worldPhase * 3.5) % (size.width * 0.035);
    for (int i = -1; i < 10; i++) {
      final x = size.width * (0.016 * i) - skyShift;
      final h = size.height * (0.028 + ((i + 7) * 11 % 4) * 0.018);
      canvas.drawRect(
        Rect.fromLTWH(x, cam.horizonY - h, size.width * 0.034, h),
        Paint()..color = const Color(0xFF3D5A6C).withOpacity(0.55),
      );
    }

    canvas.drawRect(
      _r(0, cam.horizonY, size.width, size.height - cam.horizonY),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFB8D050), Color(0xFF7CB342), Color(0xFF558B2F)],
        ).createShader(
            _r(0, cam.horizonY, size.width, size.height - cam.horizonY)),
    );

    // 3 parallele Bahnen
    for (int l = 0; l < 3; l++) {
      final lx = (l - 1).toDouble();
      final on = l == activeLane;

      final nearL = cam.project(lx - trackHalf, 1.4);
      final nearR = cam.project(lx + trackHalf, 1.4);
      final farL = cam.project(lx - trackHalf, 32);
      final farR = cam.project(lx + trackHalf, 32);

      final bed = Path()
        ..moveTo(nearL.dx, nearL.dy)
        ..lineTo(nearR.dx, nearR.dy)
        ..lineTo(farR.dx, farR.dy)
        ..lineTo(farL.dx, farL.dy)
        ..close();
      canvas.drawPath(
        bed,
        Paint()
          ..color = on
              ? const Color(0xFF8B7355).withOpacity(0.93)
              : const Color(0xFF6B5344).withOpacity(0.83),
      );

      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 2.4 : 1.6
        ..color = const Color(0xFF2C1810);
      canvas.drawLine(nearL, farL, edge);
      canvas.drawLine(nearR, farR, edge);

      for (double z = 2.2; z < 30; z += 1.7) {
        final a = cam.project(lx - trackHalf * 0.9, z);
        final b = cam.project(lx + trackHalf * 0.9, z);
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF4E342E)
            ..strokeWidth = 2.2,
        );
      }

      final pL0 = cam.project(lx - railGap, 1.4);
      final pL1 = cam.project(lx - railGap, 32);
      final pR0 = cam.project(lx + railGap, 1.4);
      final pR1 = cam.project(lx + railGap, 32);
      final rp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = on ? 3.2 : 2.0
        ..color = on ? const Color(0xFFFFF59D) : const Color(0xFFD0D5DC);
      canvas.drawLine(pL0, pL1, rp);
      canvas.drawLine(
        pR0,
        pR1,
        rp..color = on ? const Color(0xFFFFE082) : const Color(0xFF9AA3AE),
      );
    }

    // Münzen: fast konstante Größe
    for (final c in coins) {
      if (c.z < 1.8 || c.z > 30) continue;
      final p = cam.project((c.lane - 1).toDouble(), c.z, c.high ? 0.6 : 0.12);
      final r = cam.objectSize(c.z, 11.0).clamp(7.0, 12.0);
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: const [
              Color(0xFFFFFDE7),
              Color(0xFFFFD54F),
              Color(0xFFF57F17)
            ],
          ).createShader(_r(p.dx - r, p.dy - r, r * 2, r * 2)),
      );
    }

    // Hindernisse: flach, fast konstante Größe, Breite ~ Spur
    final sorted = [...obs]..sort((a, b) => b.z.compareTo(a.z));
    for (final o in sorted) {
      if (o.z < 1.8 || o.z > 30) continue;
      final base = cam.project((o.lane - 1).toDouble(), o.z);
      // Basisbreite relativ zur nahen Spur, kaum skaliert
      final w = cam.objectSize(o.z, size.width * 0.11).clamp(22.0, 48.0);
      final d = 5.0; // flache 3D-Kante, wenig Verzerrung

      if (o.kind == 0) {
        final h = cam.objectSize(o.z, 22.0).clamp(16.0, 26.0);
        _flatBox(canvas, base.dx, base.dy - h * 0.35, w, h, d,
            const Color(0xFFFFF3E0),
            const Color(0xFFFF9800),
            const Color(0xFFE65100));
      } else if (o.kind == 1) {
        final h = cam.objectSize(o.z, 48.0).clamp(34.0, 54.0);
        _flatBox(canvas, base.dx, base.dy - h * 0.65, w * 0.9, h, d,
            const Color(0xFFF3E5F5),
            const Color(0xFFAB47BC),
            const Color(0xFF6A1B9A));
      } else {
        final h = cam.objectSize(o.z, 42.0).clamp(30.0, 48.0);
        final cyan = o.hue < 0.5;
        _flatBox(
          canvas,
          base.dx,
          base.dy - h * 0.38,
          w,
          h,
          d,
          cyan ? const Color(0xFFE0F7FA) : const Color(0xFFFFEBEE),
          cyan ? const Color(0xFF26C6DA) : const Color(0xFFEF5350),
          cyan ? const Color(0xFF00838F) : const Color(0xFFC62828),
        );
      }
    }

    // Figur EXAKT auf Schienenmitte (gleiche project-Formel)
    final feet = cam.project(laneX, 3.0, 0);
    final body = cam.project(laneX, 3.0, jumpY + (jetpack ? 1.1 : 0));
    _runner(
      canvas,
      Offset(body.dx, body.dy),
      feet.dy,
      1.25,
      runPhase,
      ducking,
      jumpY > 0.12,
      ghost,
      jetpack,
      speed,
    );

    if (dead) {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.42));
    }
  }

  /// Flaches Hindernis – minimale 3D-Kante, keine starke Verzerrung
  void _flatBox(
    Canvas canvas,
    double cx,
    double cy,
    double w,
    double h,
    double d,
    Color light,
    Color mid,
    Color dark,
  ) {
    w = w.clamp(8.0, 60.0);
    h = h.clamp(8.0, 60.0);
    // rechte Kante (sehr flach)
    final right = Path()
      ..moveTo(cx + w / 2, cy - h / 2)
      ..lineTo(cx + w / 2 + d, cy - h / 2 - d * 0.2)
      ..lineTo(cx + w / 2 + d, cy + h / 2 - d * 0.2)
      ..lineTo(cx + w / 2, cy + h / 2)
      ..close();
    canvas.drawPath(right, Paint()..color = dark);
    // Oberkante
    final top = Path()
      ..moveTo(cx - w / 2, cy - h / 2)
      ..lineTo(cx - w / 2 + d * 0.15, cy - h / 2 - d * 0.25)
      ..lineTo(cx + w / 2 + d, cy - h / 2 - d * 0.2)
      ..lineTo(cx + w / 2, cy - h / 2)
      ..close();
    canvas.drawPath(top, Paint()..color = light);
    // Front
    final front = RRect.fromRectAndRadius(
      _r(cx - w / 2, cy - h / 2, w, h),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, mid, dark],
        ).createShader(front.outerRect),
    );
  }

  void _runner(
    Canvas c,
    Offset pos,
    double groundY,
    double scale,
    double phase,
    bool duck,
    bool air,
    bool ghost,
    bool jet,
    double spd,
  ) {
    final s = 30.0 * scale;
    final skin =
        ghost ? Colors.purpleAccent.withOpacity(0.9) : const Color(0xFF29B6F6);
    final dark = ghost ? Colors.deepPurple : const Color(0xFF01579B);

    final legSwing = sin(phase);
    final leg = legSwing * (duck ? 0.05 : (air ? 0.15 : 0.95));
    final arm = -legSwing * (duck ? 0.04 : (air ? 0.15 : 0.85));
    final bob = duck || air ? 0.0 : (sin(phase * 2).abs() * s * 0.12);

    // Schatten auf Boden (Schienenhöhe)
    c.drawOval(
      _r(pos.dx - s * 0.38, groundY + s * 0.08, s * 0.76, 6),
      Paint()..color = Colors.black.withOpacity(0.35),
    );

    final bodyTop =
        (duck ? pos.dy + s * 0.1 : pos.dy - s * 0.15) + bob;
    final bodyH = duck ? s * 0.45 : s * 1.0;
    final hip = Offset(pos.dx, bodyTop + bodyH * 0.55);
    final footY = groundY;

    final lp = Paint()
      ..color = dark
      ..strokeWidth = s * 0.25
      ..strokeCap = StrokeCap.round;
    final leftFoot =
        Offset(pos.dx - s * 0.28 - leg * s * 0.48, footY);
    final rightFoot =
        Offset(pos.dx + s * 0.28 + leg * s * 0.48, footY);
    c.drawLine(hip, leftFoot, lp);
    c.drawLine(hip, rightFoot, lp);
    c.drawCircle(leftFoot, s * 0.09, Paint()..color = dark);
    c.drawCircle(rightFoot, s * 0.09, Paint()..color = dark);

    final body = RRect.fromRectAndRadius(
      _r(pos.dx - s * 0.32, bodyTop, s * 0.64, bodyH),
      Radius.circular(s * 0.16),
    );
    c.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [skin, dark],
        ).createShader(body.outerRect),
    );

    final sh = Offset(pos.dx, bodyTop + bodyH * 0.08);
    final ap = Paint()
      ..color = dark
      ..strokeWidth = s * 0.18
      ..strokeCap = StrokeCap.round;
    c.drawLine(
        sh, Offset(pos.dx - s * 0.48, sh.dy + s * 0.38 + arm * s * 0.45), ap);
    c.drawLine(
        sh, Offset(pos.dx + s * 0.48, sh.dy + s * 0.38 - arm * s * 0.45), ap);

    final headY = bodyTop - s * 0.32;
    final hr = s * 0.34;
    c.drawCircle(
      Offset(pos.dx, headY),
      hr,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.95), skin, dark],
        ).createShader(_r(pos.dx - hr, headY - hr, hr * 2, hr * 2)),
    );

    if (jet) {
      final jr = 10.0;
      c.drawCircle(
        Offset(pos.dx, pos.dy + s * 0.9),
        jr,
        Paint()
          ..shader = const RadialGradient(colors: [
            Color(0xFFFFFF00),
            Color(0xFFFF6D00),
            Colors.transparent,
          ]).createShader(
              _r(pos.dx - jr, pos.dy + s * 0.9 - jr, jr * 2, jr * 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunPainter old) => true;
}
