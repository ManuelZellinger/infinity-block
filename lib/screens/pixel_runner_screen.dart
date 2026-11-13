import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Infinity Run – lange Hindernisse, stehende/begehbare Züge, Münzen, stabile Projektion
class PixelRunnerScreen extends StatefulWidget {
  const PixelRunnerScreen({super.key});
  @override
  State<PixelRunnerScreen> createState() => _PixelRunnerScreenState();
}

class _PixelRunnerScreenState extends State<PixelRunnerScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
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

  /// Auf Zugdach laufen
  bool onTrain = false;
  double onTrainT = 0;

  bool jetpack = false;
  double jetpackT = 0;
  bool ghost = false;
  double ghostT = 0;

  double _panX = 0;
  double _panY = 0;
  bool _panUsed = false;

  final List<_Obs> obs = [];
  final List<_Coin> coinList = [];
  final List<_Spark> sparks = [];
  double spawnAcc = 0;
  double coinAcc = 0;
  double worldPhase = 0;

  static const double jumpPower = 15.5;
  static const double gravity = 19.5;
  static const double kPlayerZ = 3.0;
  static const int kMaxSparks = 64;
  static const double duckDuration = 1.55;

  // kind: 0 low jump, 1 high duck, 2 block train, 3 long barrier, 4 rideable train, 5 stationary train

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      high = p.getInt('run_high') ?? 0;
      if (mounted) setState(() {});
    });
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = _last == Duration.zero
        ? 1 / 60.0
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _frame(dt.clamp(0.0, 0.05));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _addSpark(_Spark s) {
    if (sparks.length >= kMaxSparks) sparks.removeAt(0);
    sparks.add(s);
  }

  void _frame(double dt) {
    if (dead) return;

    final target = (lane - 1).toDouble();
    final d = target - laneX;
    if (d.abs() > 0.001) {
      laneX += d.clamp(-28 * dt, 28 * dt);
    } else {
      laneX = target;
    }

    dist += speed * dt;
    worldPhase += speed * dt * 0.12;
    score = dist.toInt() + coins * 5;
    speed = min(14.5, 7.2 + dist * 0.00135);

    final cadence =
        ducking ? 2.5 : (jumpY > 0.2 || onTrain ? 2.0 : 11.0 + speed * 0.5);
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
    if (onTrain) {
      onTrainT -= dt;
      if (onTrainT <= 0 || jumpY > 0.05) {
        onTrain = false;
        onTrainT = 0;
      }
    }
    if (jetpack) {
      jetpackT -= dt;
      if (jetpackT <= 0) jetpack = false;
      if (_rng.nextDouble() < 0.4) {
        _addSpark(_Spark(
          x: laneX + (_rng.nextDouble() - 0.5) * 0.15,
          z: kPlayerZ - 0.2,
          vy: 0.8 + _rng.nextDouble(),
          life: 0.3 + _rng.nextDouble() * 0.25,
          color: _rng.nextBool()
              ? const Color(0xFFFFEB3B)
              : const Color(0xFFFF6D00),
        ));
      }
    }
    if (ghost) {
      ghostT -= dt;
      if (ghostT <= 0) ghost = false;
    }

    for (final s in sparks) {
      s.life -= dt;
      s.z -= speed * dt * 0.35;
      s.y += s.vy * dt;
    }
    sparks.removeWhere((s) => s.life <= 0);

    spawnAcc += dt;
    if (spawnAcc > max(1.15, 1.9 - dist / 7000)) {
      spawnAcc = 0;
      final l = _rng.nextInt(3);
      final r = _rng.nextDouble();
      int kind;
      if (r < 0.28) {
        kind = 0; // niedrig
      } else if (r < 0.48) {
        kind = 1; // hoch ducken
      } else if (r < 0.62) {
        kind = 2; // blockierender Zug
      } else if (r < 0.76) {
        kind = 3; // langes Hindernis
      } else if (r < 0.90) {
        kind = 4; // begehbarer Zug
      } else {
        kind = 5; // stillstehend (langsam)
      }
      final length = kind == 3 ? 2.8 + _rng.nextDouble() * 2.2 : (kind == 4 || kind == 5 ? 2.2 + _rng.nextDouble() : 1.0);
      obs.add(_Obs(
        lane: l,
        z: 36,
        kind: kind,
        hue: _rng.nextDouble(),
        length: length,
        stationary: kind == 5,
      ));
    }

    coinAcc += dt;
    if (coinAcc > 0.38) {
      coinAcc = 0;
      // Münzketten auf einer Spur
      final cl = _rng.nextInt(3);
      final chain = 1 + _rng.nextInt(3);
      for (int i = 0; i < chain; i++) {
        coinList.add(_Coin(
          lane: cl,
          z: 36 + i * 1.15,
          high: _rng.nextDouble() < 0.18,
        ));
      }
    }

    for (final o in obs) {
      // Stillstehende Züge bewegen sich langsamer (wirken „stehend“ relativ)
      final factor = o.stationary ? 0.35 : 1.0;
      o.z -= speed * dt * factor;
    }
    obs.removeWhere((o) => o.z + o.length < 0.1);
    for (final c in coinList) {
      c.z -= speed * dt;
    }
    coinList.removeWhere((c) => c.z < 0.1);

    // Kollision / begehbare Züge
    if (!ghost && !jetpack && (laneX - target).abs() < 0.15) {
      for (final o in obs) {
        if (o.lane != lane) continue;
        final zFront = o.z;
        final zBack = o.z + o.length;
        final inSpan = kPlayerZ >= zFront - 0.15 && kPlayerZ <= zBack + 0.2;
        if (!inSpan) continue;

        if (o.kind == 4) {
          // Begehbarer Zug: springen → auf dem Dach
          if (jumpY > 0.55 || onTrain) {
            if (!onTrain) {
              onTrain = true;
              onTrainT = 1.8;
              jumpY = 0;
              jumpV = 0;
              HapticFeedback.selectionClick();
            }
            continue;
          }
          if (jumpY < 0.55) {
            _die();
            return;
          }
        } else if (o.kind == 5) {
          // Stillstehend: springen oder Spur wechseln
          if (jumpY < 0.7) {
            _die();
            return;
          }
        } else if (o.kind == 0 || o.kind == 3) {
          if (jumpY < 0.7 && !onTrain) {
            _die();
            return;
          }
        } else if (o.kind == 1) {
          if (!ducking && !onTrain) {
            _die();
            return;
          }
        } else if (o.kind == 2) {
          if (!onTrain) {
            _die();
            return;
          }
        }
      }
    }

    for (final c in coinList) {
      if (c.lane == lane && (c.z - kPlayerZ).abs() < 1.2) {
        if (c.high && jumpY < 0.2 && !onTrain) continue;
        if (!c.high && ducking) continue;
        coins++;
        c.z = -10;
        HapticFeedback.lightImpact();
        for (int i = 0; i < 5; i++) {
          _addSpark(_Spark(
            x: laneX + (_rng.nextDouble() - 0.5) * 0.2,
            z: kPlayerZ,
            vy: 0.5 + _rng.nextDouble(),
            life: 0.25 + _rng.nextDouble() * 0.2,
            color: const Color(0xFFFFD54F),
          ));
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _die() async {
    if (dead) return;
    dead = true;
    onTrain = false;
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
      onTrain = false;
      jetpack = false;
      ghost = false;
      obs.clear();
      coinList.clear();
      sparks.clear();
      _panX = 0;
      _panY = 0;
      _panUsed = false;
      _last = Duration.zero;
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
    if (jumpY > 0.08 && !onTrain) return;
    setState(() {
      jumpV = jumpPower;
      onTrain = false;
    });
    HapticFeedback.mediumImpact();
  }

  void _duck() {
    if (dead || !mounted || jumpY > 0.35 || onTrain) return;
    setState(() {
      ducking = true;
      duckT = duckDuration;
    });
    HapticFeedback.selectionClick();
  }

  void _jet() {
    if (dead || !mounted || jetpack) return;
    setState(() {
      jetpack = true;
      jetpackT = 7;
      jumpY = 2.4;
      onTrain = false;
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
                  const SizedBox(width: 6),
                  _chip('$coins', Icons.monetization_on_rounded,
                      Colors.amberAccent),
                  const SizedBox(width: 6),
                  _chip('HI $high', Icons.emoji_events_rounded,
                      Colors.orangeAccent),
                  const SizedBox(width: 6),
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
                  if (_panX.abs() > 14 && _panX.abs() > _panY.abs() * 1.1) {
                    _panUsed = true;
                    _lane(_panX < 0 ? -1 : 1);
                  } else if (_panY < -16 && _panY.abs() > _panX.abs()) {
                    _panUsed = true;
                    _jump();
                  } else if (_panY > 16 && _panY.abs() > _panX.abs()) {
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
                  if (vx.abs() > 80 && vx.abs() > vy.abs()) {
                    _lane(vx < 0 ? -1 : 1);
                  } else if (vy < -60) {
                    _jump();
                  } else if (vy > 60) {
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
                  isComplex: true,
                  willChange: true,
                  painter: _RunPainter(
                    laneX: laneX,
                    activeLane: lane,
                    obs: List.of(obs),
                    coins: List.of(coinList),
                    sparks: List.of(sparks),
                    jumpY: jumpY + (onTrain ? 1.15 : 0),
                    ducking: ducking,
                    runPhase: runPhase,
                    worldPhase: worldPhase,
                    jetpack: jetpack,
                    ghost: ghost,
                    dead: dead,
                    onTrain: onTrain,
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
                        onTrain
                            ? '↑ Zugdach · Spur ${lane + 1}'
                            : '←  Spur ${lane + 1} / 3  →',
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
                      child: Text(
                        score >= high && score > 0
                            ? 'Play again · New high $high'
                            : 'Play again · High $high',
                      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.32),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(v,
                style: TextStyle(
                    color: c, fontWeight: FontWeight.w700, fontSize: 12)),
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
  double length;
  bool stationary;
  _Obs({
    required this.lane,
    required this.z,
    required this.kind,
    this.hue = 0,
    this.length = 1.0,
    this.stationary = false,
  });
}

class _Coin {
  int lane;
  double z;
  bool high;
  _Coin({required this.lane, required this.z, this.high = false});
}

class _Spark {
  double x, z, y, vy, life;
  Color color;
  _Spark({
    required this.x,
    required this.z,
    this.y = 0,
    required this.vy,
    required this.life,
    required this.color,
  });
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
  final List<_Spark> sparks;
  final double jumpY;
  final bool ducking;
  final double runPhase;
  final double worldPhase;
  final bool jetpack, ghost, dead, onTrain;
  final double speed;

  static const double trackHalf = 0.125;
  static const double railGap = 0.055;

  _RunPainter({
    required this.laneX,
    required this.activeLane,
    required this.obs,
    required this.coins,
    required this.sparks,
    required this.jumpY,
    required this.ducking,
    required this.runPhase,
    required this.worldPhase,
    required this.jetpack,
    required this.ghost,
    required this.dead,
    required this.onTrain,
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
            Color(0xFF3D8BC4),
            Color(0xFF6BB3E0),
            Color(0xFFA8D4F0),
            Color(0xFFC8E0A8),
            Color(0xFF9BCF6A),
          ],
          stops: [0, 0.22, 0.38, 0.55, 1],
        ).createShader(Offset.zero & size),
    );

    final sunC = Offset(size.width * 0.82, size.height * 0.09);
    canvas.drawCircle(
      sunC,
      size.width * 0.05,
      Paint()
        ..color = const Color(0xFFFFE082).withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawCircle(
      sunC,
      size.width * 0.032,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFFFFFFEE), Color(0xFFFFEB3B), Color(0xFFFF9800)],
        ).createShader(_r(sunC.dx - 24, sunC.dy - 24, 48, 48)),
    );

    final cloudShift = (worldPhase * 2.2) % (size.width * 0.4);
    for (int i = 0; i < 5; i++) {
      final cx =
          (size.width * (0.15 + i * 0.22) - cloudShift) % (size.width + 80) - 40;
      final cy = size.height * (0.08 + (i % 3) * 0.04);
      _cloud(canvas, cx, cy, 28 + i * 4.0);
    }

    final skyShift = (worldPhase * 3.5) % (size.width * 0.035);
    for (int i = -1; i < 14; i++) {
      final x = size.width * (0.014 * i) - skyShift;
      final h = size.height * (0.028 + ((i + 7) * 11 % 5) * 0.015);
      final bw = size.width * (0.026 + (i % 3) * 0.007);
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
              .withOpacity(0.7),
      );
    }

    canvas.drawRect(
      _r(0, cam.horizonY, size.width, size.height - cam.horizonY),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFFC5E06A),
            Color(0xFF8BC34A),
            Color(0xFF689F38),
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
            Color(0xFFB0B0B0),
            Color(0xFF8A8A8A),
            Color(0xFF6A6A6A),
            Color(0xFF555555),
          ],
        ).createShader(Rect.fromPoints(bedL, bedFR)),
    );

    final rng = Random(42);
    for (int i = 0; i < 90; i++) {
      final t = rng.nextDouble();
      final side = rng.nextDouble() * 2 - 1;
      final p = cam.project(side * 1.45, 2 + t * 28);
      canvas.drawCircle(
        p,
        1.0 + rng.nextDouble() * 1.6,
        Paint()
          ..color = Color.lerp(
            const Color(0xFFCFCFCF),
            const Color(0xFF3A3A3A),
            rng.nextDouble(),
          )!
              .withOpacity(0.48),
      );
    }

    final tiePhase = (worldPhase * 2.4) % 1.5;

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
              ? const Color(0xFF5D4037).withOpacity(0.55)
              : const Color(0xFF4E342E).withOpacity(0.38),
      );

      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 2.8 : 1.8
        ..color = const Color(0xFF1A1A1A);
      canvas.drawLine(nearL, farL, edge);
      canvas.drawLine(nearR, farR, edge);

      for (double z = 2.0 + tiePhase; z < 30; z += 1.5) {
        final a = cam.project(lx - trackHalf * 0.92, z);
        final b = cam.project(lx + trackHalf * 0.92, z);
        canvas.drawLine(
          Offset(a.dx, a.dy + 1.2),
          Offset(b.dx, b.dy + 1.2),
          Paint()
            ..color = const Color(0xFF3E2723)
            ..strokeWidth = 4.2,
        );
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF6D4C41)
            ..strokeWidth = 3.3,
        );
        canvas.drawLine(
          Offset(a.dx, a.dy - 1.0),
          Offset(b.dx, b.dy - 1.0),
          Paint()
            ..color = const Color(0xFFA1887F)
            ..strokeWidth = 1.3,
        );
      }

      final pL0 = cam.project(lx - railGap, 1.35);
      final pL1 = cam.project(lx - railGap, 32);
      final pR0 = cam.project(lx + railGap, 1.35);
      final pR1 = cam.project(lx + railGap, 32);

      final shadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 4.2 : 3.0
        ..color = Colors.black.withOpacity(0.4)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(pL0.dx, pL0.dy + 1.6), Offset(pL1.dx, pL1.dy + 1.6), shadow);
      canvas.drawLine(
          Offset(pR0.dx, pR0.dy + 1.6), Offset(pR1.dx, pR1.dy + 1.6), shadow);

      final metal = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = on ? 3.8 : 2.5
        ..color = on ? const Color(0xFFF5F5F5) : const Color(0xFF90A4AE);
      canvas.drawLine(pL0, pL1, metal);
      canvas.drawLine(pR0, pR1, metal);
    }

    // Münzen – goldene 3D-Scheiben
    for (final c in coins) {
      if (c.z < 1.8 || c.z > 34) continue;
      final p = cam.project((c.lane - 1).toDouble(), c.z, c.high ? 0.65 : 0.15);
      final r = cam.objectSize(c.z, 12.0).clamp(7.5, 14.0);
      _drawCoin(canvas, p, r);
    }

    final sorted = [...obs]..sort((a, b) => b.z.compareTo(a.z));
    for (final o in sorted) {
      if (o.z > 34) continue;
      final lx = (o.lane - 1).toDouble();

      if (o.kind == 3) {
        // langes Hindernis: mehrere Segmente entlang z
        final steps = max(2, (o.length / 0.9).round());
        for (int i = 0; i < steps; i++) {
          final zz = o.z + i * (o.length / steps);
          if (zz < 1.8 || zz > 34) continue;
          final base = cam.project(lx, zz);
          final w = cam.objectSize(zz, size.width * 0.11).clamp(22.0, 48.0);
          final h = cam.objectSize(zz, 16.0).clamp(11.0, 20.0);
          _barrier(canvas, base.dx, base.dy - h * 0.28, w, h);
        }
      } else if (o.kind == 0) {
        if (o.z < 1.8) continue;
        final base = cam.project(lx, o.z);
        final w = cam.objectSize(o.z, size.width * 0.12).clamp(24.0, 52.0);
        final h = cam.objectSize(o.z, 18.0).clamp(12.0, 22.0);
        _barrier(canvas, base.dx, base.dy - h * 0.28, w, h);
      } else if (o.kind == 1) {
        if (o.z < 1.8) continue;
        final base = cam.project(lx, o.z);
        final w = cam.objectSize(o.z, size.width * 0.12).clamp(24.0, 52.0);
        final h = cam.objectSize(o.z, 50.0).clamp(34.0, 56.0);
        _highBarrier(canvas, base.dx, base.dy - h * 0.58, w * 0.9, h);
      } else {
        // Züge: 2, 4, 5 – ggf. länger
        final steps = max(1, (o.length / 1.1).round());
        for (int i = 0; i < steps; i++) {
          final zz = o.z + i * (o.length / max(1, steps));
          if (zz < 1.8 || zz > 34) continue;
          final base = cam.project(lx, zz);
          final w = cam.objectSize(zz, size.width * 0.13).clamp(26.0, 54.0);
          final h = cam.objectSize(zz, 46.0).clamp(34.0, 52.0);
          final ride = o.kind == 4;
          final park = o.kind == 5;
          _train(
            canvas,
            base.dx,
            base.dy - h * 0.32,
            w * 1.08,
            h,
            o.hue < 0.5,
            rideable: ride,
            parked: park,
          );
        }
      }
    }

    for (final s in sparks) {
      if (s.z < 1.5 || s.z > 20) continue;
      final p = cam.project(s.x, s.z, s.y);
      final a = (s.life * 2).clamp(0.0, 1.0);
      canvas.drawCircle(
        p,
        2.5 + s.life * 3,
        Paint()..color = s.color.withOpacity(0.7 * a),
      );
    }

    final feet = cam.project(laneX, 3.0, 0);
    final body = cam.project(laneX, 3.0, jumpY + (jetpack ? 1.1 : 0));
    _runner(
      canvas,
      Offset(body.dx, body.dy),
      feet.dy,
      1.36,
      runPhase,
      ducking,
      jumpY > 0.12 || onTrain,
      ghost,
      jetpack,
    );

    if (dead) {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.42));
    }
  }

  void _drawCoin(Canvas canvas, Offset p, double r) {
    canvas.drawCircle(
      p.translate(1.8, 2.4),
      r,
      Paint()..color = Colors.black.withOpacity(0.25),
    );
    // dicke Münze
    canvas.drawOval(
      _r(p.dx - r * 0.95, p.dy - r * 0.85, r * 1.9, r * 1.7),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [
            Color(0xFFFFFDE7),
            Color(0xFFFFEE58),
            Color(0xFFFFC107),
            Color(0xFFF9A825),
            Color(0xFFEF6C00),
          ],
        ).createShader(_r(p.dx - r, p.dy - r, r * 2, r * 2)),
    );
    canvas.drawCircle(
      p,
      r * 0.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFFFFF59D).withOpacity(0.9),
    );
    // $ Symbol
    final tp = TextPainter(
      text: TextSpan(
        text: r > 10 ? '€' : '•',
        style: TextStyle(
          color: const Color(0xFF5D4037).withOpacity(0.85),
          fontSize: r * 0.9,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
    canvas.drawCircle(
      Offset(p.dx - r * 0.28, p.dy - r * 0.32),
      r * 0.2,
      Paint()..color = Colors.white.withOpacity(0.7),
    );
  }

  void _cloud(Canvas canvas, double cx, double cy, double s) {
    final p = Paint()..color = Colors.white.withOpacity(0.55);
    canvas.drawCircle(Offset(cx, cy), s * 0.45, p);
    canvas.drawCircle(Offset(cx + s * 0.35, cy + 2), s * 0.38, p);
    canvas.drawCircle(Offset(cx - s * 0.3, cy + 3), s * 0.32, p);
    canvas.drawCircle(Offset(cx + s * 0.1, cy - s * 0.15), s * 0.28, p);
  }

  void _barrier(Canvas canvas, double cx, double cy, double w, double h) {
    w = w.clamp(10.0, 56.0);
    h = h.clamp(10.0, 28.0);
    canvas.drawOval(
      _r(cx - w * 0.4, cy + h * 0.4, w * 0.8, 5),
      Paint()..color = Colors.black.withOpacity(0.25),
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
          colors: [
            Color(0xFFFFF59D),
            Color(0xFFFFCA28),
            Color(0xFFFFA000),
            Color(0xFFE65100),
          ],
        ).createShader(body.outerRect),
    );
    for (int i = 0; i < 4; i++) {
      final x = cx - w * 0.38 + i * w * 0.22;
      canvas.drawRect(
        _r(x, cy - h * 0.28, w * 0.1, h * 0.55),
        Paint()..color = const Color(0xFF212121).withOpacity(0.4),
      );
    }
  }

  void _highBarrier(Canvas canvas, double cx, double cy, double w, double h) {
    w = w.clamp(10.0, 56.0);
    h = h.clamp(20.0, 60.0);
    canvas.drawOval(
      _r(cx - w * 0.4, cy + h * 0.42, w * 0.8, 5),
      Paint()..color = Colors.black.withOpacity(0.25),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        _r(cx - w * 0.48, cy - h * 0.5, w * 0.12, h),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF6A1B9A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        _r(cx + w * 0.36, cy - h * 0.5, w * 0.12, h),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF6A1B9A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        _r(cx - w * 0.5, cy - h * 0.48, w, h * 0.22),
        const Radius.circular(3),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE1BEE7), Color(0xFF9C27B0), Color(0xFF4A148C)],
        ).createShader(_r(cx - w * 0.5, cy - h * 0.48, w, h * 0.22)),
    );
  }

  void _train(
    Canvas canvas,
    double cx,
    double cy,
    double w,
    double h,
    bool cyan, {
    bool rideable = false,
    bool parked = false,
  }) {
    w = w.clamp(12.0, 60.0);
    h = h.clamp(22.0, 56.0);
    final light = rideable
        ? const Color(0xFFE8F5E9)
        : parked
            ? const Color(0xFFFFF3E0)
            : cyan
                ? const Color(0xFFE0F7FA)
                : const Color(0xFFFFEBEE);
    final mid = rideable
        ? const Color(0xFF66BB6A)
        : parked
            ? const Color(0xFFFFB74D)
            : cyan
                ? const Color(0xFF26C6DA)
                : const Color(0xFFEF5350);
    final dark = rideable
        ? const Color(0xFF2E7D32)
        : parked
            ? const Color(0xFFE65100)
            : cyan
                ? const Color(0xFF006064)
                : const Color(0xFFB71C1C);

    canvas.drawOval(
      _r(cx - w * 0.45, cy + h * 0.42, w * 0.9, 6),
      Paint()..color = Colors.black.withOpacity(0.3),
    );

    final d = 6.5;
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

    // Dach-Markierung für begehbar
    if (rideable) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _r(cx - w * 0.45, cy - h * 0.55, w * 0.9, 5),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFA5D6A7),
      );
    }

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

    for (int i = 0; i < 3; i++) {
      final wx = cx - w * 0.32 + i * (w * 0.26);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _r(wx, cy - h * 0.28, w * 0.16, h * 0.28),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFB3E5FC).withOpacity(0.92),
      );
    }
    canvas.drawCircle(
      Offset(cx - w * 0.28, cy + h * 0.32),
      3.8,
      Paint()..color = parked ? const Color(0xFFFF5252) : const Color(0xFFFFF59D),
    );
    canvas.drawCircle(
      Offset(cx + w * 0.28, cy + h * 0.32),
      3.8,
      Paint()..color = parked ? const Color(0xFFFF5252) : const Color(0xFFFFF59D),
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
  ) {
    final s = 32.0 * scale;
    final skin =
        ghost ? Colors.purpleAccent.withOpacity(0.9) : const Color(0xFF42A5F5);
    final shirt = ghost ? Colors.deepPurple : const Color(0xFF1565C0);
    final pants = ghost ? Colors.deepPurple.shade800 : const Color(0xFF0D47A1);

    final legSwing = sin(phase);
    final leg = legSwing * (duck ? 0.04 : (air ? 0.12 : 0.95));
    final arm = -legSwing * (duck ? 0.03 : (air ? 0.12 : 0.85));
    final bob = duck || air ? 0.0 : (sin(phase * 2).abs() * s * 0.12);

    c.drawOval(
      _r(pos.dx - s * 0.36, groundY + s * 0.06, s * 0.72, 6),
      Paint()..color = Colors.black.withOpacity(0.35),
    );

    final bodyTop = (duck ? pos.dy + s * 0.1 : pos.dy - s * 0.18) + bob;
    final bodyH = duck ? s * 0.4 : s * 0.98;
    final hip = Offset(pos.dx, bodyTop + bodyH * 0.58);
    final footY = groundY;

    final lp = Paint()
      ..color = pants
      ..strokeWidth = s * 0.28
      ..strokeCap = StrokeCap.round;
    final leftFoot = Offset(pos.dx - s * 0.26 - leg * s * 0.48, footY);
    final rightFoot = Offset(pos.dx + s * 0.26 + leg * s * 0.48, footY);
    c.drawLine(hip, leftFoot, lp);
    c.drawLine(hip, rightFoot, lp);
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

    final sh = Offset(pos.dx, bodyTop + bodyH * 0.12);
    final ap = Paint()
      ..color = shirt
      ..strokeWidth = s * 0.2
      ..strokeCap = StrokeCap.round;
    c.drawLine(
        sh, Offset(pos.dx - s * 0.5, sh.dy + s * 0.4 + arm * s * 0.42), ap);
    c.drawLine(
        sh, Offset(pos.dx + s * 0.5, sh.dy + s * 0.4 - arm * s * 0.42), ap);

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
    c.drawCircle(Offset(pos.dx - hr * 0.3, headY - hr * 0.05), hr * 0.13,
        Paint()..color = Colors.white);
    c.drawCircle(Offset(pos.dx + hr * 0.3, headY - hr * 0.05), hr * 0.13,
        Paint()..color = Colors.white);
    c.drawCircle(Offset(pos.dx - hr * 0.3, headY - hr * 0.05), hr * 0.06,
        Paint()..color = const Color(0xFF1A237E));
    c.drawCircle(Offset(pos.dx + hr * 0.3, headY - hr * 0.05), hr * 0.06,
        Paint()..color = const Color(0xFF1A237E));

    if (jet) {
      final jr = 12.0;
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
