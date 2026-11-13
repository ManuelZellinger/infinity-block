import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Infinity Run – Subway-Steuerung, bessere Züge & Figur, stabile Projektion
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

  static const double jumpPower = 14.2;
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
      laneX += d.clamp(-24 * dt, 24 * dt);
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
      final kind = r < 0.40 ? 0 : (r < 0.68 ? 1 : 2);
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
                // Subway Surfers: Wischen links/rechts = Spur,
                // hoch = springen, runter = ducken
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
                  // horizontal zuerst (Spurwechsel)
                  if (_panX.abs() > 18 && _panX.abs() > _panY.abs() * 1.15) {
                    _panUsed = true;
                    _lane(_panX < 0 ? -1 : 1);
                  } else if (_panY < -20 && _panY.abs() > _panX.abs()) {
                    _panUsed = true;
                    _jump();
                  } else if (_panY > 20 && _panY.abs() > _panX.abs()) {
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
                  if (vx.abs() > 100 && vx.abs() > vy.abs() * 1.1) {
                    _lane(vx < 0 ? -1 : 1);
                  } else if (vy < -80) {
                    _jump();
                  } else if (vy > 80) {
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
    final spread = nearSpread * (1.0 - t * 0.30);
    final sx = size.width * 0.5 + lx * size.width * spread;
    final sy =
        groundY + (horizonY - groundY) * t - y * (1.0 - t) * size.height * 0.09;
    return Offset(sx, sy);
  }

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

  static const double trackHalf = 0.125;
  static const double railGap = 0.055;

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
          colors: [
            Color(0xFF5BA8D0),
            Color(0xFF8EC5E8),
            Color(0xFFC5DCA0),
            Color(0xFFA8D070),
          ],
          stops: [0, 0.30, 0.52, 1],
        ).createShader(Offset.zero & size),
    );

    final sunC = Offset(size.width * 0.82, size.height * 0.1);
    canvas.drawCircle(
      sunC,
      size.width * 0.05,
      Paint()
        ..color = const Color(0xFFFFE082).withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawCircle(
      sunC,
      size.width * 0.032,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFFFFFFCC), Color(0xFFFFC107)],
        ).createShader(_r(sunC.dx - 22, sunC.dy - 22, 44, 44)),
    );

    final skyShift = (worldPhase * 3.5) % (size.width * 0.035);
    for (int i = -1; i < 12; i++) {
      final x = size.width * (0.015 * i) - skyShift;
      final h = size.height * (0.03 + ((i + 7) * 11 % 5) * 0.016);
      final bw = size.width * (0.028 + (i % 3) * 0.008);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, cam.horizonY - h, bw, h),
          const Radius.circular(2),
        ),
        Paint()
          ..color = Color.lerp(
            const Color(0xFF2C4A5C),
            const Color(0xFF5A7A8C),
            ((i + 3) % 4) / 4,
          )!
              .withOpacity(0.65),
      );
    }

    canvas.drawRect(
      _r(0, cam.horizonY, size.width, size.height - cam.horizonY),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFFB8D44A),
            Color(0xFF7CB342),
            Color(0xFF558B2F),
          ],
        ).createShader(
            _r(0, cam.horizonY, size.width, size.height - cam.horizonY)),
    );

    final bedL = cam.project(-1.55, 1.3);
    final bedR = cam.project(1.55, 1.3);
    final bedFL = cam.project(-1.55, 32);
    final bedFR = cam.project(1.55, 32);
    final bigBed = Path()
      ..moveTo(bedL.dx, bedL.dy)
      ..lineTo(bedR.dx, bedR.dy)
      ..lineTo(bedFR.dx, bedFR.dy)
      ..lineTo(bedFL.dx, bedFL.dy)
      ..close();
    canvas.drawPath(
      bigBed,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFF9E9E9E),
            Color(0xFF757575),
            Color(0xFF616161),
          ],
        ).createShader(Rect.fromPoints(bedL, bedFR)),
    );

    final rng = Random(42);
    for (int i = 0; i < 70; i++) {
      final t = rng.nextDouble();
      final side = rng.nextDouble() * 2 - 1;
      final p = cam.project(side * 1.4, 2 + t * 28);
      canvas.drawCircle(
        p,
        1.2 + rng.nextDouble() * 1.4,
        Paint()
          ..color = Color.lerp(
            const Color(0xFFBDBDBD),
            const Color(0xFF424242),
            rng.nextDouble(),
          )!
              .withOpacity(0.45),
      );
    }

    for (int l = 0; l < 3; l++) {
      final lx = (l - 1).toDouble();
      final on = l == activeLane;

      final nearL = cam.project(lx - trackHalf, 1.35);
      final nearR = cam.project(lx + trackHalf, 1.35);
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
              ? const Color(0xFF5D4037).withOpacity(0.5)
              : const Color(0xFF4E342E).withOpacity(0.35),
      );

      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 2.8 : 1.8
        ..color = const Color(0xFF212121);
      canvas.drawLine(nearL, farL, edge);
      canvas.drawLine(nearR, farR, edge);

      for (double z = 2.0; z < 30; z += 1.55) {
        final a = cam.project(lx - trackHalf * 0.92, z);
        final b = cam.project(lx + trackHalf * 0.92, z);
        canvas.drawLine(
          Offset(a.dx, a.dy + 1.2),
          Offset(b.dx, b.dy + 1.2),
          Paint()
            ..color = const Color(0xFF3E2723)
            ..strokeWidth = 4.0,
        );
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF6D4C41)
            ..strokeWidth = 3.2,
        );
        canvas.drawLine(
          Offset(a.dx, a.dy - 1.0),
          Offset(b.dx, b.dy - 1.0),
          Paint()
            ..color = const Color(0xFF8D6E63)
            ..strokeWidth = 1.2,
        );
      }

      final pL0 = cam.project(lx - railGap, 1.35);
      final pL1 = cam.project(lx - railGap, 32);
      final pR0 = cam.project(lx + railGap, 1.35);
      final pR1 = cam.project(lx + railGap, 32);

      final shadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 4.0 : 2.8
        ..color = Colors.black.withOpacity(0.35)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(pL0.dx, pL0.dy + 1.5), Offset(pL1.dx, pL1.dy + 1.5), shadow);
      canvas.drawLine(
          Offset(pR0.dx, pR0.dy + 1.5), Offset(pR1.dx, pR1.dy + 1.5), shadow);

      final metal = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = on ? 3.6 : 2.4
        ..color = on ? const Color(0xFFECEFF1) : const Color(0xFF90A4AE);
      canvas.drawLine(pL0, pL1, metal);
      canvas.drawLine(pR0, pR1, metal);

      if (on) {
        canvas.drawLine(
          pL0,
          pL1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = Colors.white.withOpacity(0.55),
        );
        canvas.drawLine(
          pR0,
          pR1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = Colors.white.withOpacity(0.45),
        );
      }
    }

    for (final c in coins) {
      if (c.z < 1.8 || c.z > 30) continue;
      final p = cam.project((c.lane - 1).toDouble(), c.z, c.high ? 0.6 : 0.12);
      final r = cam.objectSize(c.z, 11.0).clamp(7.0, 12.0);
      canvas.drawCircle(
        p.translate(1.5, 2),
        r * 0.95,
        Paint()..color = Colors.black.withOpacity(0.2),
      );
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.4),
            colors: const [
              Color(0xFFFFFDE7),
              Color(0xFFFFD54F),
              Color(0xFFF9A825),
              Color(0xFFF57F17),
            ],
          ).createShader(_r(p.dx - r, p.dy - r, r * 2, r * 2)),
      );
      canvas.drawCircle(
        Offset(p.dx - r * 0.25, p.dy - r * 0.3),
        r * 0.22,
        Paint()..color = Colors.white.withOpacity(0.7),
      );
    }

    final sorted = [...obs]..sort((a, b) => b.z.compareTo(a.z));
    for (final o in sorted) {
      if (o.z < 1.8 || o.z > 30) continue;
      final base = cam.project((o.lane - 1).toDouble(), o.z);
      final w = cam.objectSize(o.z, size.width * 0.12).clamp(24.0, 52.0);

      if (o.kind == 0) {
        // niedrige Barriere – springen
        final h = cam.objectSize(o.z, 20.0).clamp(14.0, 24.0);
        _barrier(canvas, base.dx, base.dy - h * 0.3, w, h);
      } else if (o.kind == 1) {
        // hohe Barriere – ducken
        final h = cam.objectSize(o.z, 52.0).clamp(36.0, 58.0);
        _highBarrier(canvas, base.dx, base.dy - h * 0.62, w * 0.88, h);
      } else {
        // Zug
        final h = cam.objectSize(o.z, 44.0).clamp(32.0, 50.0);
        final cyan = o.hue < 0.5;
        _train(
          canvas,
          base.dx,
          base.dy - h * 0.35,
          w * 1.08,
          h,
          cyan,
        );
      }
    }

    final feet = cam.project(laneX, 3.0, 0);
    final body = cam.project(laneX, 3.0, jumpY + (jetpack ? 1.1 : 0));
    _runner(
      canvas,
      Offset(body.dx, body.dy),
      feet.dy,
      1.32,
      runPhase,
      ducking,
      jumpY > 0.12,
      ghost,
      jetpack,
    );

    if (dead) {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.42));
    }
  }

  void _barrier(Canvas canvas, double cx, double cy, double w, double h) {
    w = w.clamp(10.0, 56.0);
    h = h.clamp(10.0, 30.0);
    canvas.drawOval(
      _r(cx - w * 0.4, cy + h * 0.4, w * 0.8, 5),
      Paint()..color = Colors.black.withOpacity(0.22),
    );
    final body = RRect.fromRectAndRadius(
      _r(cx - w / 2, cy - h / 2, w, h),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE082), Color(0xFFFFA000), Color(0xFFE65100)],
        ).createShader(body.outerRect),
    );
    // Warnstreifen
    for (int i = 0; i < 3; i++) {
      final x = cx - w * 0.35 + i * w * 0.28;
      canvas.drawRect(
        _r(x, cy - h * 0.25, w * 0.12, h * 0.5),
        Paint()..color = const Color(0xFF212121).withOpacity(0.35),
      );
    }
  }

  void _highBarrier(Canvas canvas, double cx, double cy, double w, double h) {
    w = w.clamp(10.0, 56.0);
    h = h.clamp(20.0, 62.0);
    canvas.drawOval(
      _r(cx - w * 0.4, cy + h * 0.42, w * 0.8, 5),
      Paint()..color = Colors.black.withOpacity(0.22),
    );
    final body = RRect.fromRectAndRadius(
      _r(cx - w / 2, cy - h / 2, w, h),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE1BEE7), Color(0xFFAB47BC), Color(0xFF6A1B9A)],
        ).createShader(body.outerRect),
    );
    // Querbalken oben (ducken!)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        _r(cx - w * 0.48, cy - h * 0.42, w * 0.96, h * 0.18),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF4A148C),
    );
  }

  void _train(Canvas canvas, double cx, double cy, double w, double h, bool cyan) {
    w = w.clamp(12.0, 60.0);
    h = h.clamp(22.0, 56.0);
    final light = cyan ? const Color(0xFFE0F7FA) : const Color(0xFFFFEBEE);
    final mid = cyan ? const Color(0xFF26C6DA) : const Color(0xFFEF5350);
    final dark = cyan ? const Color(0xFF006064) : const Color(0xFFB71C1C);

    canvas.drawOval(
      _r(cx - w * 0.45, cy + h * 0.42, w * 0.9, 6),
      Paint()..color = Colors.black.withOpacity(0.28),
    );

    // Seitenfläche
    final d = 6.0;
    final right = Path()
      ..moveTo(cx + w / 2, cy - h / 2)
      ..lineTo(cx + w / 2 + d, cy - h / 2 - d * 0.2)
      ..lineTo(cx + w / 2 + d, cy + h / 2 - d * 0.2)
      ..lineTo(cx + w / 2, cy + h / 2)
      ..close();
    canvas.drawPath(right, Paint()..color = dark);

    final top = Path()
      ..moveTo(cx - w / 2, cy - h / 2)
      ..lineTo(cx - w / 2 + d * 0.15, cy - h / 2 - d * 0.25)
      ..lineTo(cx + w / 2 + d, cy - h / 2 - d * 0.2)
      ..lineTo(cx + w / 2, cy - h / 2)
      ..close();
    canvas.drawPath(top, Paint()..color = light);

    final front = RRect.fromRectAndRadius(
      _r(cx - w / 2, cy - h / 2, w, h),
      const Radius.circular(5),
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

    // Fensterreihe
    for (int i = 0; i < 3; i++) {
      final wx = cx - w * 0.32 + i * (w * 0.26);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _r(wx, cy - h * 0.28, w * 0.16, h * 0.28),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFB3E5FC).withOpacity(0.9),
      );
    }
    // untere Fenster
    for (int i = 0; i < 3; i++) {
      final wx = cx - w * 0.32 + i * (w * 0.26);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _r(wx, cy + h * 0.02, w * 0.16, h * 0.2),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFF81D4FA).withOpacity(0.7),
      );
    }
    // Lichter vorne
    canvas.drawCircle(
      Offset(cx - w * 0.28, cy + h * 0.32),
      3.5,
      Paint()..color = const Color(0xFFFFF59D),
    );
    canvas.drawCircle(
      Offset(cx + w * 0.28, cy + h * 0.32),
      3.5,
      Paint()..color = const Color(0xFFFFF59D),
    );
  }

  /// Kompakter Läufer (Subway-ähnlich), Füße auf Schiene
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
  ) {
    final s = 31.0 * scale;
    final skin =
        ghost ? Colors.purpleAccent.withOpacity(0.9) : const Color(0xFF42A5F5);
    final shirt = ghost ? Colors.deepPurple : const Color(0xFF1565C0);
    final pants = ghost ? Colors.deepPurple.shade800 : const Color(0xFF0D47A1);

    final legSwing = sin(phase);
    final leg = legSwing * (duck ? 0.04 : (air ? 0.12 : 0.9));
    final arm = -legSwing * (duck ? 0.03 : (air ? 0.12 : 0.8));
    final bob = duck || air ? 0.0 : (sin(phase * 2).abs() * s * 0.1);

    c.drawOval(
      _r(pos.dx - s * 0.35, groundY + s * 0.06, s * 0.7, 5),
      Paint()..color = Colors.black.withOpacity(0.32),
    );

    final bodyTop = (duck ? pos.dy + s * 0.08 : pos.dy - s * 0.18) + bob;
    final bodyH = duck ? s * 0.42 : s * 0.95;
    final hip = Offset(pos.dx, bodyTop + bodyH * 0.58);
    final footY = groundY;

    // Beine
    final lp = Paint()
      ..color = pants
      ..strokeWidth = s * 0.28
      ..strokeCap = StrokeCap.round;
    final leftFoot = Offset(pos.dx - s * 0.26 - leg * s * 0.45, footY);
    final rightFoot = Offset(pos.dx + s * 0.26 + leg * s * 0.45, footY);
    c.drawLine(hip, leftFoot, lp);
    c.drawLine(hip, rightFoot, lp);
    // Schuhe
    c.drawRRect(
      RRect.fromRectAndRadius(
        _r(leftFoot.dx - s * 0.14, leftFoot.dy - s * 0.05, s * 0.28, s * 0.12),
        Radius.circular(s * 0.04),
      ),
      Paint()..color = const Color(0xFF212121),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        _r(rightFoot.dx - s * 0.14, rightFoot.dy - s * 0.05, s * 0.28, s * 0.12),
        Radius.circular(s * 0.04),
      ),
      Paint()..color = const Color(0xFF212121),
    );

    // Körper
    final body = RRect.fromRectAndRadius(
      _r(pos.dx - s * 0.3, bodyTop, s * 0.6, bodyH),
      Radius.circular(s * 0.14),
    );
    c.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [skin, shirt, pants],
        ).createShader(body.outerRect),
    );

    // Arme
    final sh = Offset(pos.dx, bodyTop + bodyH * 0.12);
    final ap = Paint()
      ..color = shirt
      ..strokeWidth = s * 0.2
      ..strokeCap = StrokeCap.round;
    c.drawLine(
        sh, Offset(pos.dx - s * 0.5, sh.dy + s * 0.4 + arm * s * 0.42), ap);
    c.drawLine(
        sh, Offset(pos.dx + s * 0.5, sh.dy + s * 0.4 - arm * s * 0.42), ap);

    // Kopf
    final headY = bodyTop - s * 0.3;
    final hr = s * 0.33;
    c.drawCircle(
      Offset(pos.dx, headY),
      hr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.3),
          colors: [Colors.white.withOpacity(0.95), skin, shirt],
        ).createShader(_r(pos.dx - hr, headY - hr, hr * 2, hr * 2)),
    );
    // Augen
    c.drawCircle(Offset(pos.dx - hr * 0.3, headY - hr * 0.05), hr * 0.13,
        Paint()..color = Colors.white);
    c.drawCircle(Offset(pos.dx + hr * 0.3, headY - hr * 0.05), hr * 0.13,
        Paint()..color = Colors.white);
    c.drawCircle(Offset(pos.dx - hr * 0.3, headY - hr * 0.05), hr * 0.06,
        Paint()..color = const Color(0xFF1A237E));
    c.drawCircle(Offset(pos.dx + hr * 0.3, headY - hr * 0.05), hr * 0.06,
        Paint()..color = const Color(0xFF1A237E));

    if (jet) {
      final jr = 11.0;
      c.drawCircle(
        Offset(pos.dx, pos.dy + s * 0.88),
        jr,
        Paint()
          ..shader = const RadialGradient(colors: [
            Color(0xFFFFFF00),
            Color(0xFFFF6D00),
            Colors.transparent,
          ]).createShader(
              _r(pos.dx - jr, pos.dy + s * 0.88 - jr, jr * 2, jr * 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunPainter old) => true;
}
