import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Infinity Run – gerade Schienen, flache Perspektive, erweiterte Hindernisse
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
    if (spawnAcc > max(1.5, 2.25 - dist / 5200)) {
      spawnAcc = 0;
      final l = _rng.nextInt(3);
      final r = _rng.nextDouble();
      // 0 barriere, 1 duck, 2 zug, 3 dual-barrier, 4 ramp, 5 cone
      int kind;
      if (r < 0.22) {
        kind = 0;
      } else if (r < 0.40) {
        kind = 1;
      } else if (r < 0.58) {
        kind = 2;
      } else if (r < 0.72) {
        kind = 3;
      } else if (r < 0.86) {
        kind = 4;
      } else {
        kind = 5;
      }
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
        // kind 0,3,4,5 = springen; 1 = ducken; 2 = Zug ausweichen
        if (o.kind == 1 && !ducking) {
          _die();
          return;
        }
        if (o.kind == 2) {
          _die();
          return;
        }
        if ((o.kind == 0 || o.kind == 3 || o.kind == 4 || o.kind == 5) && jumpY < 1.2) {
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

/// Flache lineare 1/z-Perspektive – keine Bogen-/Berg-Krümmung
class _Cam {
  final Size size;
  final double horizonY;
  final double nearY;
  final double focal;
  static const double spread = 0.36;

  _Cam(this.size)
      : horizonY = size.height * 0.28,
        nearY = size.height * 0.88,
        focal = 14.0;

  Offset project(double lx, double z, [double y = 0]) {
    final zz = z.clamp(1.6, 48.0);
    final s = focal / zz;
    final cx = size.width * 0.5;
    // rein linear in x – keine zusätzliche Krümmung
    final sx = cx + lx * s * size.width * spread;
    // t linear in 1/z-Nähe: gerade Strecke Richtung Horizont
    final t = ((48 - zz) / 46.4).clamp(0.0, 1.0);
    final sy = horizonY + (nearY - horizonY) * t - y * s * 7.5;
    return Offset(sx, sy);
  }

  double scale(double z) {
    final zz = z.clamp(1.6, 48.0);
    return (focal / zz * 12.0).clamp(5.0, 40.0);
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
          stops: [0, 0.35, 1],
        ).createShader(Offset.zero & size),
    );

    // Sonne
    final sunC = Offset(size.width * 0.84, size.height * 0.08);
    canvas.drawCircle(
      sunC,
      size.width * 0.05,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFFFFFFA0), Color(0xFFFFC107)],
        ).createShader(_r(sunC.dx - size.width * 0.05, sunC.dy - size.width * 0.05, size.width * 0.1, size.width * 0.1)),
    );

    // Skyline
    final skyShift = (worldPhase * 6) % (size.width * 0.07);
    for (int i = -1; i < 16; i++) {
      final x = size.width * (0.01 * i) - skyShift + size.width * 0.02;
      final h = size.height * (0.045 + ((i + 20) * 11 % 7) * 0.028);
      canvas.drawRect(
        Rect.fromLTWH(x, cam.horizonY - h, size.width * 0.045, h),
        Paint()..color = const Color(0xFF4A6A80).withOpacity(0.6),
      );
    }

    // Flacher Boden (kein Bogen)
    canvas.drawRect(
      _r(0, cam.horizonY, size.width, size.height - cam.horizonY),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFB8D850), Color(0xFF8BC34A), Color(0xFF558B2F)],
        ).createShader(_r(0, cam.horizonY, size.width, size.height - cam.horizonY)),
    );

    // Schotter – gerade Bahnen
    for (double z = 2.4; z < 46; z += 0.75) {
      final a = cam.project(-1.35, z);
      final b = cam.project(1.35, z);
      final sc = cam.scale(z);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xFF6D5A40).withOpacity(0.4)
          ..strokeWidth = (sc * 0.58).clamp(4.0, 38.0),
      );
    }

    // Schwellen – parallel, gerade
    final sleep = Paint()..color = const Color(0xFF5D4037);
    for (double z = 2.8; z < 44; z += 1.5) {
      final a = cam.project(-1.3, z);
      final b = cam.project(1.3, z);
      final sc = cam.scale(z);
      canvas.drawLine(a, b, sleep..strokeWidth = (sc * 0.12).clamp(1.5, 11.0));
    }

    // 3 Schienen – gerade Linien (lineare Projektion, keine Krümmung)
    for (int l = 0; l < 3; l++) {
      final lx = (l - 1).toDouble();
      final on = l == activeLane;
      final left = Path();
      final right = Path();
      var first = true;
      for (double z = 2.0; z <= 44; z += 0.5) {
        const g = 0.13;
        final pL = cam.project(lx - g, z);
        final pR = cam.project(lx + g, z);
        if (first) {
          left.moveTo(pL.dx, pL.dy);
          right.moveTo(pR.dx, pR.dy);
          first = false;
        } else {
          left.lineTo(pL.dx, pL.dy);
          right.lineTo(pR.dx, pR.dy);
        }
      }
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = on ? 4.0 : 2.4
        ..color = on ? const Color(0xFFFFF59D) : const Color(0xFFE8ECF0);
      canvas.drawPath(left, p);
      canvas.drawPath(
        right,
        p..color = on ? const Color(0xFFFFE082) : const Color(0xFFA8B0BC),
      );
    }

    // Münzen
    for (final c in coins) {
      if (c.z < 1.1 || c.z > 44) continue;
      final sc = cam.scale(c.z);
      final p = cam.project((c.lane - 1).toDouble(), c.z, c.high ? 1.05 : 0.3);
      final r = (sc * 0.22).clamp(4.0, 17.0);
      canvas.drawCircle(Offset(p.dx + 1.2, p.dy + 2.2), r, Paint()..color = Colors.black38);
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
      final w = (sc * 0.85).clamp(8.0, 60.0);
      final d = (sc * 0.24).clamp(2.5, 16.0);

      canvas.drawOval(
        _r(base.dx - w * 0.55, base.dy + 2, w * 1.1, w * 0.22),
        Paint()..color = Colors.black.withOpacity(0.38),
      );

      if (o.kind == 0) {
        // Gelbe Barriere
        final h = (sc * 0.5).clamp(8.0, 38.0);
        _box3d(canvas, base.dx, base.dy - h * 0.45, w, h, d,
            const Color(0xFFFFFDE7), const Color(0xFFFFB300), const Color(0xFFE65100));
        final stripe = Paint()..color = const Color(0xFF212121);
        for (int i = 0; i < 5; i++) {
          canvas.drawRect(
            _r(base.dx - w * 0.42 + i * w * 0.18, base.dy - h * 0.55, w * 0.09, h * 0.3),
            stripe,
          );
        }
      } else if (o.kind == 1) {
        // Duck-Hindernis
        final h = (sc * 1.32).clamp(15.0, 88.0);
        _box3d(canvas, base.dx, base.dy - h * 0.78, w * 0.95, h, d,
            const Color(0xFFF3E5F5), const Color(0xFFAB47BC), const Color(0xFF4A148C));
        canvas.drawRect(
          _r(base.dx - w * 0.55, base.dy - h * 0.38, w * 1.1, h * 0.12),
          Paint()..color = const Color(0xFF6A1B9A),
        );
      } else if (o.kind == 2) {
        // Zug
        final h = (sc * 1.5).clamp(18.0, 100.0);
        final cyan = o.hue < 0.5;
        final light = cyan ? const Color(0xFFE0F7FA) : const Color(0xFFFFEBEE);
        final mid = cyan ? const Color(0xFF00ACC1) : const Color(0xFFEF5350);
        final dark = cyan ? const Color(0xFF006064) : const Color(0xFFB71C1C);
        _box3d(canvas, base.dx, base.dy - h * 0.48, w * 1.22, h, d * 1.4, light, mid, dark);
        canvas.drawRect(
          _r(base.dx - w * 0.58, base.dy - h * 1.0, w * 1.16, h * 0.09),
          Paint()..color = dark,
        );
        final wr = (sc * 0.15).clamp(3.0, 12.0);
        final win = Paint()..color = const Color(0xFFE3F2FD).withOpacity(0.95);
        for (final dx in [-0.38, -0.13, 0.13, 0.38]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              _r(base.dx + w * dx - wr * 0.5, base.dy - h * 0.58, wr, wr * 1.2),
              const Radius.circular(2),
            ),
            win,
          );
        }
        canvas.drawCircle(
          Offset(base.dx, base.dy - h * 0.1),
          (sc * 0.1).clamp(2.2, 7.0),
          Paint()..color = const Color(0xFFFFF59D),
        );
        final wheel = Paint()..color = const Color(0xFF212121);
        for (final dx in [-0.4, 0.4]) {
          canvas.drawCircle(
            Offset(base.dx + w * dx, base.dy + 2),
            (sc * 0.12).clamp(2.5, 8.0),
            wheel,
          );
        }
      } else if (o.kind == 3) {
        // Doppel-Barriere (zwei Balken übereinander)
        final h = (sc * 0.38).clamp(6.0, 28.0);
        _box3d(canvas, base.dx, base.dy - h * 0.4, w * 0.95, h, d,
            const Color(0xFFFFECB3), const Color(0xFFFF8F00), const Color(0xFFE65100));
        _box3d(canvas, base.dx, base.dy - h * 1.35, w * 0.95, h, d,
            const Color(0xFFFFECB3), const Color(0xFFFF8F00), const Color(0xFFE65100));
      } else if (o.kind == 4) {
        // Rampe / Keil – springen
        final h = (sc * 0.7).clamp(10.0, 48.0);
        final path = Path()
          ..moveTo(base.dx - w * 0.5, base.dy)
          ..lineTo(base.dx + w * 0.5, base.dy)
          ..lineTo(base.dx + w * 0.15, base.dy - h)
          ..lineTo(base.dx - w * 0.35, base.dy - h * 0.35)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: const [Color(0xFF8D6E63), Color(0xFFBCAAA4)],
            ).createShader(_r(base.dx - w * 0.5, base.dy - h, w, h)),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFF4E342E),
        );
      } else {
        // Warnkegel
        final h = (sc * 0.85).clamp(12.0, 52.0);
        final cone = Path()
          ..moveTo(base.dx, base.dy - h)
          ..lineTo(base.dx + w * 0.4, base.dy)
          ..lineTo(base.dx - w * 0.4, base.dy)
          ..close();
        canvas.drawPath(
          cone,
          Paint()
            ..shader = LinearGradient(
              colors: const [Color(0xFFFFCC80), Color(0xFFFF6D00)],
            ).createShader(_r(base.dx - w * 0.4, base.dy - h, w * 0.8, h)),
        );
        // weiße Ringe
        canvas.drawLine(
          Offset(base.dx - w * 0.22, base.dy - h * 0.35),
          Offset(base.dx + w * 0.22, base.dy - h * 0.35),
          Paint()
            ..color = Colors.white
            ..strokeWidth = (sc * 0.06).clamp(1.5, 4.0),
        );
        canvas.drawLine(
          Offset(base.dx - w * 0.15, base.dy - h * 0.6),
          Offset(base.dx + w * 0.15, base.dy - h * 0.6),
          Paint()
            ..color = Colors.white
            ..strokeWidth = (sc * 0.05).clamp(1.2, 3.5),
        );
      }
    }

    // Figur – feste playerZ, gleiche Projektion wie Schienen
    const playerZ = 3.0;
    final raw = cam.project(laneX, playerZ, jumpY + (jetpack ? 1.45 : 0));
    final m = size.width * 0.06;
    final px = raw.dx.clamp(m, size.width - m);
    final py = raw.dy.clamp(size.height * 0.32, size.height * 0.92);
    final pScale = cam.scale(playerZ);
    _runner(
      canvas,
      Offset(px, py),
      (pScale * 0.07).clamp(1.1, 1.6),
      runPhase,
      ducking,
      jumpY > 0.2,
      ghost,
      jetpack,
    );

    if (dead) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.48));
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
    w = w.clamp(4.0, 110.0);
    h = h.clamp(4.0, 110.0);
    d = d.clamp(1.5, 24.0);
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
    final s = 28.0 * scale;
    final skin =
        ghost ? Colors.purpleAccent.withOpacity(0.9) : const Color(0xFF29B6F6);
    final dark = ghost ? Colors.deepPurple : const Color(0xFF0277BD);
    final leg = sin(phase) * (duck ? 0.1 : (air ? 0.25 : 0.85));
    final arm = -sin(phase) * (duck ? 0.08 : (air ? 0.25 : 0.75));
    final bob = duck || air ? 0.0 : sin(phase * 2) * s * 0.09;

    c.drawOval(
      _r(pos.dx - s * 0.55, pos.dy + s * 1.3, s * 1.1, 10),
      Paint()..color = Colors.black.withOpacity(0.4),
    );

    final bodyTop = (duck ? pos.dy + s * 0.15 : pos.dy - s * 0.12) + bob;
    final bodyH = duck ? s * 0.52 : s * 1.08;
    final hip = Offset(pos.dx, bodyTop + bodyH * 0.55);
    final footY = pos.dy + s * 1.22;

    final lp = Paint()
      ..color = dark
      ..strokeWidth = s * 0.27
      ..strokeCap = StrokeCap.round;
    c.drawLine(hip, Offset(pos.dx - s * 0.42 - leg * s * 0.5, footY), lp);
    c.drawLine(hip, Offset(pos.dx + s * 0.42 + leg * s * 0.5, footY), lp);

    final body = RRect.fromRectAndRadius(
      _r(pos.dx - s * 0.36, bodyTop, s * 0.72, bodyH),
      Radius.circular(s * 0.18),
    );
    c.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(colors: [skin, dark]).createShader(body.outerRect),
    );

    final sh = Offset(pos.dx, bodyTop + bodyH * 0.08);
    final ap = Paint()
      ..color = dark
      ..strokeWidth = s * 0.2
      ..strokeCap = StrokeCap.round;
    c.drawLine(sh, Offset(pos.dx - s * 0.58, sh.dy + s * 0.42 + arm * s * 0.45), ap);
    c.drawLine(sh, Offset(pos.dx + s * 0.58, sh.dy + s * 0.42 - arm * s * 0.45), ap);

    final headY = bodyTop - s * 0.38;
    final hr = s * 0.38;
    c.drawCircle(
      Offset(pos.dx, headY),
      hr,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.95), skin],
        ).createShader(_r(pos.dx - hr, headY - hr, hr * 2, hr * 2)),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        _r(pos.dx - s * 0.28, headY - s * 0.05, s * 0.56, s * 0.24),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF0D47A1).withOpacity(0.9),
    );

    if (jet) {
      final jr = 12.0;
      c.drawCircle(
        Offset(pos.dx, pos.dy + s * 1.05),
        jr,
        Paint()
          ..shader = const RadialGradient(colors: [
            Color(0xFFFFFF00),
            Color(0xFFFF6D00),
            Colors.transparent,
          ]).createShader(_r(pos.dx - jr, pos.dy + s * 1.05 - jr, jr * 2, jr * 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunPainter old) => true;
}
