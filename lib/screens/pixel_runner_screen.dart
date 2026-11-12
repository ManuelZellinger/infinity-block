import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Infinity Run – parallele Spuren (Subway-Stil), Figur fest auf der Bahn
class PixelRunnerScreen extends StatefulWidget {
  const PixelRunnerScreen({super.key});
  @override
  State<PixelRunnerScreen> createState() => _PixelRunnerScreenState();
}

class _PixelRunnerScreenState extends State<PixelRunnerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;
  final _rng = Random();

  int lane = 1; // 0 links, 1 mitte, 2 rechts
  double laneX = 0.0; // -1 .. 1

  double speed = 6.5;
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
  static const double gravity = 22.0;
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
      laneX += d.clamp(-20 * dt, 20 * dt);
    } else {
      laneX = target;
    }

    dist += speed * dt;
    worldPhase += speed * dt * 0.12;
    score = dist.toInt() + coins * 5;
    speed = min(14.0, 6.5 + dist * 0.0014);

    final cadence = ducking ? 3.4 : (jumpY > 0.25 ? 2.3 : 8.8 + speed * 0.48);
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
    if (spawnAcc > max(1.35, 2.1 - dist / 5600)) {
      spawnAcc = 0;
      final l = _rng.nextInt(3);
      final r = _rng.nextDouble();
      final kind = r < 0.4 ? 0 : (r < 0.68 ? 1 : 2);
      obs.add(_Obs(lane: l, z: 38, kind: kind, hue: _rng.nextDouble()));
    }

    coinAcc += dt;
    if (coinAcc > 0.36) {
      coinAcc = 0;
      coinList.add(_Coin(lane: _rng.nextInt(3), z: 38, high: _rng.nextDouble() < 0.25));
    }

    for (final o in obs) {
      o.z -= speed * dt;
    }
    obs.removeWhere((o) => o.z < 0.08);
    for (final c in coinList) {
      c.z -= speed * dt;
    }
    coinList.removeWhere((c) => c.z < 0.08);

    // Enges Fenster: erst kurz vor dem Hindernis springen/ducken
    if (!ghost && !jetpack && (laneX - target).abs() < 0.15) {
      for (final o in obs) {
        if (o.lane != lane) continue;
        final dz = o.z - kPlayerZ;
        if (dz < 0.08 || dz > 0.95) continue;
        if (o.kind == 0 && jumpY < 0.95) {
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
      if (c.lane == lane && (c.z - kPlayerZ).abs() < 1.2) {
        if (c.high && jumpY < 0.3) continue;
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
      speed = 6.5;
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
    if (jumpY > 0.06) return;
    setState(() => jumpV = jumpPower);
    HapticFeedback.mediumImpact();
  }

  void _duck() {
    if (dead || !mounted || jumpY > 0.3) return;
    setState(() {
      ducking = true;
      duckT = 1.45;
    });
    HapticFeedback.selectionClick();
  }

  void _jet() {
    if (dead || !mounted || jetpack) return;
    setState(() {
      jetpack = true;
      jetpackT = 7.5;
      jumpY = 2.6;
    });
  }

  void _ghost() {
    if (dead || !mounted || ghost) return;
    setState(() {
      ghost = true;
      ghostT = 5.5;
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
                    icon: const Icon(Icons.home_rounded, color: Colors.white70, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  _chip('$score', Icons.speed_rounded),
                  const SizedBox(width: 8),
                  _chip('$coins', Icons.monetization_on_rounded, Colors.amberAccent),
                  const SizedBox(width: 8),
                  _chip('Spur ${lane + 1}', Icons.view_column_rounded, Colors.lightGreenAccent),
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
                      _btn(Icons.keyboard_arrow_up_rounded, _jump, const Color(0xFFFFB300)),
                      const SizedBox(width: 10),
                      _btn(Icons.keyboard_arrow_down_rounded, _duck, const Color(0xFFCE93D8)),
                      const SizedBox(width: 10),
                      _btn(Icons.rocket_launch_rounded, _jet, const Color(0xFF00E5FF)),
                      const SizedBox(width: 10),
                      _btn(Icons.blur_on_rounded, _ghost, const Color(0xFFE040FB)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _btn(Icons.chevron_left_rounded, () => _lane(-1), Colors.white),
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
                      _btn(Icons.chevron_right_rounded, () => _lane(1), Colors.white),
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
            Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );

  Widget _btn(IconData icon, VoidCallback on, Color c) => Material(
        color: Colors.black.withOpacity(0.36),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: on,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(width: 54, height: 46, child: Icon(icon, color: c, size: 28)),
        ),
      );
}

class _Obs {
  int lane;
  double z;
  int kind;
  double hue;
  _Obs({required this.lane, required this.z, required this.kind, this.hue = 0});
}

class _Coin {
  int lane;
  double z;
  bool high;
  _Coin({required this.lane, required this.z, this.high = false});
}

/// Perspektiv-Kamera: 3 parallele Spuren, kein seitliches Auffächern
class _Cam {
  final Size size;
  final double horizonY;
  final double groundY;
  /// Abstand der Spur-Mitten am Boden (Spieler-Ebene), in Anteil der Breite
  static const double nearSpread = 0.22;

  _Cam(this.size)
      : horizonY = size.height * 0.30,
        groundY = size.height * 0.78;

  /// z: 1 (nah) … 40 (fern). lx: -1 / 0 / 1
  Offset project(double lx, double z, [double y = 0]) {
    final t = ((z - 1.0) / 39.0).clamp(0.0, 1.0); // 0 = nah, 1 = fern
    // Spur-Breite nimmt linear ab → parallele Schienen, kein Bogen
    final spread = nearSpread * (1.0 - t * 0.92);
    final sx = size.width * 0.5 + lx * size.width * spread;
    final sy = groundY + (horizonY - groundY) * t - y * (1.0 - t) * size.height * 0.12;
    return Offset(sx, sy);
  }

  double scale(double z) {
    final t = ((z - 1.0) / 39.0).clamp(0.0, 1.0);
    return (28.0 * (1.0 - t * 0.85)).clamp(4.0, 28.0);
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

  static const double trackHalf = 0.11;
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
  });

  Rect _r(double l, double t, double w, double h) =>
      Rect.fromLTWH(l, t, w.abs().clamp(0.5, 5000), h.abs().clamp(0.5, 5000));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 40 || size.height < 40) return;
    final cam = _Cam(size);

    // Himmel
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5BA8D0), Color(0xFF9BCFE8), Color(0xFFC8E0A0)],
          stops: [0, 0.38, 1],
        ).createShader(Offset.zero & size),
    );

    // Sonne
    final sunC = Offset(size.width * 0.82, size.height * 0.09);
    canvas.drawCircle(
      sunC,
      size.width * 0.038,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFFFFFFB0), Color(0xFFFFC107)],
        ).createShader(_r(sunC.dx - 28, sunC.dy - 28, 56, 56)),
    );

    // Skyline
    final skyShift = (worldPhase * 5) % (size.width * 0.05);
    for (int i = -1; i < 14; i++) {
      final x = size.width * (0.014 * i) - skyShift;
      final h = size.height * (0.035 + ((i + 11) * 17 % 5) * 0.022);
      canvas.drawRect(
        Rect.fromLTWH(x, cam.horizonY - h, size.width * 0.038, h),
        Paint()..color = const Color(0xFF3D5A6C).withOpacity(0.65),
      );
    }

    // Gras
    canvas.drawRect(
      _r(0, cam.horizonY, size.width, size.height - cam.horizonY),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFB8D050), Color(0xFF7CB342), Color(0xFF558B2F)],
        ).createShader(_r(0, cam.horizonY, size.width, size.height - cam.horizonY)),
    );

    // === 3 parallele Bahnen ===
    for (int l = 0; l < 3; l++) {
      final lx = (l - 1).toDouble();
      final on = l == activeLane;

      // Schotter als Trapez (nah → fern)
      final bed = Path();
      final nearL = cam.project(lx - trackHalf, 1.2);
      final nearR = cam.project(lx + trackHalf, 1.2);
      final farL = cam.project(lx - trackHalf, 38);
      final farR = cam.project(lx + trackHalf, 38);
      bed.moveTo(nearL.dx, nearL.dy);
      bed.lineTo(nearR.dx, nearR.dy);
      bed.lineTo(farR.dx, farR.dy);
      bed.lineTo(farL.dx, farL.dy);
      bed.close();
      canvas.drawPath(
        bed,
        Paint()
          ..color = on
              ? const Color(0xFF8B7355).withOpacity(0.92)
              : const Color(0xFF6B5344).withOpacity(0.82),
      );

      // Dunkle Ränder
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 2.6 : 1.8
        ..color = const Color(0xFF2C1810);
      canvas.drawLine(nearL, farL, edge);
      canvas.drawLine(nearR, farR, edge);

      // Schwellen
      for (double z = 2.0; z < 36; z += 1.4) {
        final a = cam.project(lx - trackHalf * 0.88, z);
        final b = cam.project(lx + trackHalf * 0.88, z);
        final sc = cam.scale(z);
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF4E342E)
            ..strokeWidth = (sc * 0.12).clamp(1.2, 8.0),
        );
      }

      // Zwei Schienen (gerade Linien nah→fern)
      final pL0 = cam.project(lx - railGap, 1.2);
      final pL1 = cam.project(lx - railGap, 38);
      final pR0 = cam.project(lx + railGap, 1.2);
      final pR1 = cam.project(lx + railGap, 38);
      final rp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = on ? 3.4 : 2.2
        ..color = on ? const Color(0xFFFFF59D) : const Color(0xFFD0D5DC);
      canvas.drawLine(pL0, pL1, rp);
      canvas.drawLine(
        pR0,
        pR1,
        rp..color = on ? const Color(0xFFFFE082) : const Color(0xFF9AA3AE),
      );
    }

    // Münzen
    for (final c in coins) {
      if (c.z < 1.5 || c.z > 36) continue;
      final sc = cam.scale(c.z);
      final p = cam.project((c.lane - 1).toDouble(), c.z, c.high ? 0.9 : 0.2);
      final r = (sc * 0.28).clamp(3.5, 14.0);
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: const [Color(0xFFFFFDE7), Color(0xFFFFD54F), Color(0xFFF57F17)],
          ).createShader(_r(p.dx - r, p.dy - r, r * 2, r * 2)),
      );
    }

    // Hindernisse
    final sorted = [...obs]..sort((a, b) => b.z.compareTo(a.z));
    for (final o in sorted) {
      if (o.z < 1.5 || o.z > 36) continue;
      final sc = cam.scale(o.z);
      final base = cam.project((o.lane - 1).toDouble(), o.z);
      final w = (sc * 1.1).clamp(7.0, 52.0);
      final d = (sc * 0.3).clamp(2.0, 14.0);

      if (o.kind == 0) {
        final h = (sc * 0.55).clamp(7.0, 32.0);
        _box3d(canvas, base.dx, base.dy - h * 0.4, w, h, d,
            const Color(0xFFFFFDE7), const Color(0xFFFFB300), const Color(0xFFE65100));
      } else if (o.kind == 1) {
        final h = (sc * 1.4).clamp(12.0, 78.0);
        _box3d(canvas, base.dx, base.dy - h * 0.72, w * 0.95, h, d,
            const Color(0xFFF3E5F5), const Color(0xFFAB47BC), const Color(0xFF4A148C));
      } else {
        final h = (sc * 1.6).clamp(14.0, 90.0);
        final cyan = o.hue < 0.5;
        final light = cyan ? const Color(0xFFE0F7FA) : const Color(0xFFFFEBEE);
        final mid = cyan ? const Color(0xFF00ACC1) : const Color(0xFFEF5350);
        final dark = cyan ? const Color(0xFF006064) : const Color(0xFFB71C1C);
        _box3d(canvas, base.dx, base.dy - h * 0.42, w * 1.15, h, d * 1.3, light, mid, dark);
      }
    }

    // Figur: gleiche project()-Formel, immer auf laneX
    final raw = cam.project(laneX, 3.0, jumpY + (jetpack ? 1.2 : 0));
    final px = raw.dx;
    final py = raw.dy;
    final pScale = cam.scale(3.0);
    _runner(
      canvas,
      Offset(px, py),
      (pScale * 0.095).clamp(1.0, 1.5),
      runPhase,
      ducking,
      jumpY > 0.15,
      ghost,
      jetpack,
    );

    if (dead) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.45));
    }
  }

  void _box3d(
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
    w = w.clamp(4.0, 100.0);
    h = h.clamp(4.0, 100.0);
    d = d.clamp(1.5, 20.0);
    final right = Path()
      ..moveTo(cx + w / 2, cy - h / 2)
      ..lineTo(cx + w / 2 + d, cy - h / 2 - d * 0.3)
      ..lineTo(cx + w / 2 + d, cy + h / 2 - d * 0.3)
      ..lineTo(cx + w / 2, cy + h / 2)
      ..close();
    canvas.drawPath(right, Paint()..color = dark);
    final top = Path()
      ..moveTo(cx - w / 2, cy - h / 2)
      ..lineTo(cx - w / 2 + d * 0.22, cy - h / 2 - d * 0.35)
      ..lineTo(cx + w / 2 + d, cy - h / 2 - d * 0.3)
      ..lineTo(cx + w / 2, cy - h / 2)
      ..close();
    canvas.drawPath(top, Paint()..color = light);
    final front = RRect.fromRectAndRadius(
      _r(cx - w / 2, cy - h / 2, w, h),
      Radius.circular((w * 0.05).clamp(1.0, 4.0)),
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
    double scale,
    double phase,
    bool duck,
    bool air,
    bool ghost,
    bool jet,
  ) {
    final s = 26.0 * scale;
    final skin =
        ghost ? Colors.purpleAccent.withOpacity(0.9) : const Color(0xFF29B6F6);
    final dark = ghost ? Colors.deepPurple : const Color(0xFF01579B);
    final leg = sin(phase) * (duck ? 0.08 : (air ? 0.22 : 0.82));
    final arm = -sin(phase) * (duck ? 0.06 : (air ? 0.22 : 0.72));
    final bob = duck || air ? 0.0 : sin(phase * 2) * s * 0.08;

    c.drawOval(
      _r(pos.dx - s * 0.45, pos.dy + s * 1.15, s * 0.9, 8),
      Paint()..color = Colors.black.withOpacity(0.4),
    );

    final bodyTop = (duck ? pos.dy + s * 0.12 : pos.dy - s * 0.1) + bob;
    final bodyH = duck ? s * 0.48 : s * 1.02;
    final hip = Offset(pos.dx, bodyTop + bodyH * 0.55);
    final footY = pos.dy + s * 1.12;

    final lp = Paint()
      ..color = dark
      ..strokeWidth = s * 0.24
      ..strokeCap = StrokeCap.round;
    c.drawLine(hip, Offset(pos.dx - s * 0.38 - leg * s * 0.48, footY), lp);
    c.drawLine(hip, Offset(pos.dx + s * 0.38 + leg * s * 0.48, footY), lp);

    final body = RRect.fromRectAndRadius(
      _r(pos.dx - s * 0.34, bodyTop, s * 0.68, bodyH),
      Radius.circular(s * 0.17),
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
    c.drawLine(sh, Offset(pos.dx - s * 0.5, sh.dy + s * 0.38 + arm * s * 0.42), ap);
    c.drawLine(sh, Offset(pos.dx + s * 0.5, sh.dy + s * 0.38 - arm * s * 0.42), ap);

    final headY = bodyTop - s * 0.36;
    final hr = s * 0.36;
    c.drawCircle(
      Offset(pos.dx, headY),
      hr,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.95), skin, dark],
        ).createShader(_r(pos.dx - hr, headY - hr, hr * 2, hr * 2)),
    );

    if (jet) {
      final jr = 11.0;
      c.drawCircle(
        Offset(pos.dx, pos.dy + s * 1.0),
        jr,
        Paint()
          ..shader = const RadialGradient(colors: [
            Color(0xFFFFFF00),
            Color(0xFFFF6D00),
            Colors.transparent,
          ]).createShader(_r(pos.dx - jr, pos.dy + s - jr, jr * 2, jr * 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunPainter old) => true;
}
