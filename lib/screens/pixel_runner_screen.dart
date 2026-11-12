import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Infinity Run – 3 klar getrennte Bahnen (Schienen nicht über volle Breite)
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

  double speed = 7.2;
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

  static const double jumpPower = 13.8;
  static const double gravity = 20.0;
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
    if (d.abs() > 0.004) {
      laneX += d.clamp(-12 * dt, 12 * dt);
    } else {
      laneX = target;
    }

    dist += speed * dt;
    worldPhase += speed * dt * 0.15;
    score = dist.toInt() + coins * 5;
    speed = min(15.5, 7.2 + dist * 0.0018);

    final cadence = ducking ? 3.8 : (jumpY > 0.3 ? 2.6 : 9.5 + speed * 0.55);
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
    if (spawnAcc > max(1.55, 2.3 - dist / 5200)) {
      spawnAcc = 0;
      final l = _rng.nextInt(3);
      final r = _rng.nextDouble();
      final kind = r < 0.34 ? 0 : (r < 0.62 ? 1 : 2);
      obs.add(_Obs(lane: l, z: 42, kind: kind, hue: _rng.nextDouble()));
    }

    coinAcc += dt;
    if (coinAcc > 0.4) {
      coinAcc = 0;
      coinList.add(_Coin(lane: _rng.nextInt(3), z: 42, high: _rng.nextDouble() < 0.32));
    }

    for (final o in obs) {
      o.z -= speed * dt;
    }
    obs.removeWhere((o) => o.z < 0.12);
    for (final c in coinList) {
      c.z -= speed * dt;
    }
    coinList.removeWhere((c) => c.z < 0.12);

    if (!ghost && !jetpack && (laneX - target).abs() < 0.22) {
      for (final o in obs) {
        if (o.lane != lane) continue;
        final dz = o.z - kPlayerZ;
        if (dz < 0.0 || dz > 1.8) continue;
        if (o.kind == 0 && jumpY < 1.2) {
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
      if (c.lane == lane && (c.z - kPlayerZ).abs() < 1.65) {
        if (c.high && jumpY < 0.4) continue;
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
      speed = 7.2;
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
    if (jumpY > 0.1) return;
    setState(() => jumpV = jumpPower);
    HapticFeedback.mediumImpact();
  }

  void _duck() {
    if (dead || !mounted || jumpY > 0.4) return;
    setState(() {
      ducking = true;
      duckT = 1.6;
    });
    HapticFeedback.selectionClick();
  }

  void _jet() {
    if (dead || !mounted || jetpack) return;
    setState(() {
      jetpack = true;
      jetpackT = 8;
      jumpY = 2.9;
    });
  }

  void _ghost() {
    if (dead || !mounted || ghost) return;
    setState(() {
      ghost = true;
      ghostT = 6;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3D8AB8),
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
                  if (_panX.abs() > 20 && _panX.abs() > _panY.abs()) {
                    _panUsed = true;
                    _lane(_panX < 0 ? -1 : 1);
                  } else if (_panY < -28 && _panY.abs() > _panX.abs()) {
                    _panUsed = true;
                    _jump();
                  } else if (_panY > 28 && _panY.abs() > _panX.abs()) {
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
                  if (vx.abs() > 110 && vx.abs() > vy.abs()) {
                    _lane(vx < 0 ? -1 : 1);
                  } else if (vy < -90) {
                    _jump();
                  } else if (vy > 90) {
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

class _Cam {
  final Size size;
  final double horizonY;
  final double nearY;
  final double focal;
  /// Abstand der Bahn-Mitten (größer = klarere Trennung)
  static const double spread = 0.42;

  _Cam(this.size)
      : horizonY = size.height * 0.22,
        nearY = size.height * 0.9,
        focal = 12.0;

  Offset project(double lx, double z, [double y = 0]) {
    final zz = z.clamp(1.4, 48.0);
    final s = focal / zz;
    final cx = size.width * 0.5;
    final sx = cx + lx * s * size.width * spread;
    final t = ((48 - zz) / 46.6).clamp(0.0, 1.0);
    final sy = horizonY + (nearY - horizonY) * t - y * s * 8.5;
    return Offset(sx, sy);
  }

  double scale(double z) {
    final zz = z.clamp(1.4, 48.0);
    return (focal / zz * 13.0).clamp(5.0, 44.0);
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

  /// Halbe Breite einer einzelnen Bahn (Schotter + Schienen)
  static const double trackHalf = 0.18;
  /// Schienenabstand innerhalb einer Bahn
  static const double railGap = 0.11;

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
          colors: [Color(0xFF6BB3E0), Color(0xFFA8D8F0), Color(0xFFD4E8A0)],
          stops: [0, 0.32, 1],
        ).createShader(Offset.zero & size),
    );

    final sunC = Offset(size.width * 0.84, size.height * 0.07);
    canvas.drawCircle(
      sunC,
      size.width * 0.045,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFFFFFFA0), Color(0xFFFFC107)],
        ).createShader(_r(
          sunC.dx - size.width * 0.045,
          sunC.dy - size.width * 0.045,
          size.width * 0.09,
          size.width * 0.09,
        )),
    );

    final skyShift = (worldPhase * 8) % (size.width * 0.08);
    for (int i = -1; i < 18; i++) {
      final x = size.width * (0.01 * i) - skyShift + size.width * 0.02;
      final h = size.height * (0.048 + ((i + 20) * 11 % 7) * 0.03);
      canvas.drawRect(
        Rect.fromLTWH(x, cam.horizonY - h, size.width * 0.048, h),
        Paint()..color = const Color(0xFF4A6A80).withOpacity(0.65),
      );
    }

    // Gras über die ganze Fläche – Bahnen liegen nur als schmale Streifen drauf
    canvas.drawRect(
      _r(0, cam.horizonY, size.width, size.height - cam.horizonY),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFC0D860), Color(0xFF8BC34A), Color(0xFF558B2F)],
        ).createShader(_r(0, cam.horizonY, size.width, size.height - cam.horizonY)),
    );

    // === Drei getrennte Bahnen (nicht über die volle Breite) ===
    for (int l = 0; l < 3; l++) {
      final lx = (l - 1).toDouble();
      final on = l == activeLane;

      // Schotterbett nur unter dieser Bahn
      for (double z = 2.2; z < 46; z += 0.65) {
        final a = cam.project(lx - trackHalf, z);
        final b = cam.project(lx + trackHalf, z);
        final sc = cam.scale(z);
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = (on ? const Color(0xFF7A6550) : const Color(0xFF6D5A40))
                .withOpacity(on ? 0.55 : 0.4)
            ..strokeWidth = (sc * 0.55).clamp(3.0, 36.0)
            ..strokeCap = StrokeCap.round,
        );
      }

      // Schwellen nur auf dieser Bahn
      final sleep = Paint()..color = const Color(0xFF5D4037);
      for (double z = 2.5; z < 44; z += 1.5) {
        final a = cam.project(lx - trackHalf * 0.95, z);
        final b = cam.project(lx + trackHalf * 0.95, z);
        final sc = cam.scale(z);
        canvas.drawLine(
          a,
          b,
          sleep..strokeWidth = (sc * 0.12).clamp(1.5, 11.0),
        );
      }

      // Zwei Schienen dieser Bahn
      final left = Path();
      final right = Path();
      var first = true;
      for (double z = 2.0; z <= 44; z += 0.5) {
        final pL = cam.project(lx - railGap, z);
        final pR = cam.project(lx + railGap, z);
        if (first) {
          left.moveTo(pL.dx, pL.dy);
          right.moveTo(pR.dx, pR.dy);
          first = false;
        } else {
          left.lineTo(pL.dx, pL.dy);
          right.lineTo(pR.dx, pR.dy);
        }
      }
      final railPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = on ? 3.8 : 2.4
        ..color = on ? const Color(0xFFFFF59D) : const Color(0xFFE8ECF0);
      canvas.drawPath(left, railPaint);
      canvas.drawPath(
        right,
        railPaint..color = on ? const Color(0xFFFFE082) : const Color(0xFFA8B0BC),
      );

      // Leichter Glow auf aktiver Bahn
      if (on) {
        canvas.drawPath(
          left,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..color = const Color(0xFFFFE082).withOpacity(0.18),
        );
        canvas.drawPath(
          right,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..color = const Color(0xFFFFE082).withOpacity(0.18),
        );
      }
    }

    // Münzen
    for (final c in coins) {
      if (c.z < 1.1 || c.z > 44) continue;
      final sc = cam.scale(c.z);
      final p = cam.project((c.lane - 1).toDouble(), c.z, c.high ? 1.1 : 0.32);
      final r = (sc * 0.23).clamp(4.0, 18.0);
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
      if (o.z < 1.1 || o.z > 44) continue;
      final sc = cam.scale(o.z);
      final base = cam.project((o.lane - 1).toDouble(), o.z);
      final w = (sc * 0.88).clamp(8.0, 64.0);
      final d = (sc * 0.26).clamp(2.5, 18.0);

      if (o.kind == 0) {
        final h = (sc * 0.52).clamp(8.0, 40.0);
        _box3d(canvas, base.dx, base.dy - h * 0.45, w, h, d,
            const Color(0xFFFFFDE7), const Color(0xFFFFB300), const Color(0xFFE65100));
      } else if (o.kind == 1) {
        final h = (sc * 1.35).clamp(16.0, 92.0);
        _box3d(canvas, base.dx, base.dy - h * 0.78, w * 0.98, h, d,
            const Color(0xFFF3E5F5), const Color(0xFFAB47BC), const Color(0xFF4A148C));
      } else {
        final h = (sc * 1.55).clamp(18.0, 105.0);
        final cyan = o.hue < 0.5;
        final light = cyan ? const Color(0xFFE0F7FA) : const Color(0xFFFFEBEE);
        final mid = cyan ? const Color(0xFF00ACC1) : const Color(0xFFEF5350);
        final dark = cyan ? const Color(0xFF006064) : const Color(0xFFB71C1C);
        _box3d(canvas, base.dx, base.dy - h * 0.48, w * 1.28, h, d * 1.5, light, mid, dark);
      }
    }

    // Figur
    const playerZ = 3.0;
    final raw = cam.project(laneX, playerZ, jumpY + (jetpack ? 1.5 : 0));
    final m = size.width * 0.05;
    final px = raw.dx.clamp(m, size.width - m);
    final py = raw.dy.clamp(size.height * 0.3, size.height * 0.93);
    final pScale = cam.scale(playerZ);
    _runner(
      canvas,
      Offset(px, py),
      (pScale * 0.072).clamp(1.15, 1.65),
      runPhase,
      ducking,
      jumpY > 0.2,
      ghost,
      jetpack,
    );

    if (dead) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.5));
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
    w = w.clamp(4.0, 120.0);
    h = h.clamp(4.0, 120.0);
    d = d.clamp(1.5, 26.0);
    final right = Path()
      ..moveTo(cx + w / 2, cy - h / 2)
      ..lineTo(cx + w / 2 + d, cy - h / 2 - d * 0.34)
      ..lineTo(cx + w / 2 + d, cy + h / 2 - d * 0.34)
      ..lineTo(cx + w / 2, cy + h / 2)
      ..close();
    canvas.drawPath(right, Paint()..color = dark);
    final top = Path()
      ..moveTo(cx - w / 2, cy - h / 2)
      ..lineTo(cx - w / 2 + d * 0.26, cy - h / 2 - d * 0.4)
      ..lineTo(cx + w / 2 + d, cy - h / 2 - d * 0.34)
      ..lineTo(cx + w / 2, cy - h / 2)
      ..close();
    canvas.drawPath(top, Paint()..color = light);
    final front = RRect.fromRectAndRadius(
      _r(cx - w / 2, cy - h / 2, w, h),
      Radius.circular((w * 0.05).clamp(1.0, 5.0)),
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
    final s = 29.0 * scale;
    final skin =
        ghost ? Colors.purpleAccent.withOpacity(0.9) : const Color(0xFF29B6F6);
    final dark = ghost ? Colors.deepPurple : const Color(0xFF01579B);
    final leg = sin(phase) * (duck ? 0.1 : (air ? 0.28 : 0.88));
    final arm = -sin(phase) * (duck ? 0.08 : (air ? 0.28 : 0.78));
    final bob = duck || air ? 0.0 : sin(phase * 2) * s * 0.1;

    c.drawOval(
      _r(pos.dx - s * 0.58, pos.dy + s * 1.32, s * 1.16, 11),
      Paint()..color = Colors.black.withOpacity(0.42),
    );

    final bodyTop = (duck ? pos.dy + s * 0.16 : pos.dy - s * 0.14) + bob;
    final bodyH = duck ? s * 0.54 : s * 1.12;
    final hip = Offset(pos.dx, bodyTop + bodyH * 0.55);
    final footY = pos.dy + s * 1.25;

    final lp = Paint()
      ..color = dark
      ..strokeWidth = s * 0.28
      ..strokeCap = StrokeCap.round;
    c.drawLine(hip, Offset(pos.dx - s * 0.44 - leg * s * 0.52, footY), lp);
    c.drawLine(hip, Offset(pos.dx + s * 0.44 + leg * s * 0.52, footY), lp);

    final body = RRect.fromRectAndRadius(
      _r(pos.dx - s * 0.38, bodyTop, s * 0.76, bodyH),
      Radius.circular(s * 0.19),
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
      ..strokeWidth = s * 0.22
      ..strokeCap = StrokeCap.round;
    c.drawLine(sh, Offset(pos.dx - s * 0.6, sh.dy + s * 0.44 + arm * s * 0.48), ap);
    c.drawLine(sh, Offset(pos.dx + s * 0.6, sh.dy + s * 0.44 - arm * s * 0.48), ap);

    final headY = bodyTop - s * 0.4;
    final hr = s * 0.4;
    c.drawCircle(
      Offset(pos.dx, headY),
      hr,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.95), skin, dark],
        ).createShader(_r(pos.dx - hr, headY - hr, hr * 2, hr * 2)),
    );

    if (jet) {
      final jr = 13.0;
      c.drawCircle(
        Offset(pos.dx, pos.dy + s * 1.1),
        jr,
        Paint()
          ..shader = const RadialGradient(colors: [
            Color(0xFFFFFF00),
            Color(0xFFFF6D00),
            Colors.transparent,
          ]).createShader(_r(pos.dx - jr, pos.dy + s * 1.1 - jr, jr * 2, jr * 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunPainter old) => true;
}
