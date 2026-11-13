import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Infinity Run – Beine beim Sprung anziehen, keine Zug-Überlappung
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
  double dustAcc = 0;

  static const double jumpPower = 16.8;
  static const double gravity = 20.5;
  static const double kPlayerZ = 3.0;
  static const int kMaxSparks = 64;
  static const int kMaxObs = 18;
  static const int kMaxCoins = 24;
  static const double duckDuration = 1.8;
  static const double kCoinMinGap = 2.8;
  static const double kObsMinGap = 9.0;
  /// Züge brauchen mehr Abstand (auch spurübergreifend)
  static const double kTrainMinGap = 14.0;

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

  bool _isTrainKind(int kind) => kind == 2 || kind == 4 || kind == 5;

  bool _laneBusy(int l, double z, double length, double minGap) {
    for (final o in obs) {
      if (o.lane != l) continue;
      final a0 = o.z;
      final a1 = o.z + o.length;
      final b0 = z;
      final b1 = z + length;
      if (b0 < a1 + minGap && b1 + minGap > a0) return true;
    }
    return false;
  }

  /// Züge: Abstand auf allen Spuren (kein Stapel von 3 Zügen nebeneinander)
  bool _trainZoneBusy(double z, double length) {
    final gap = kTrainMinGap;
    for (final o in obs) {
      if (!_isTrainKind(o.kind)) continue;
      final a0 = o.z;
      final a1 = o.z + o.length;
      final b0 = z;
      final b1 = z + length;
      if (b0 < a1 + gap && b1 + gap > a0) return true;
    }
    return false;
  }

  bool _coinBusy(int l, double z) {
    for (final c in coinList) {
      if (c.lane != l) continue;
      if ((c.z - z).abs() < kCoinMinGap) return true;
    }
    return false;
  }

  void _spawnCoins() {
    if (coinList.length >= kMaxCoins) return;
    var cl = _rng.nextInt(3);
    for (int tries = 0; tries < 3; tries++) {
      if (!_coinBusy(cl, 40)) break;
      cl = (cl + 1) % 3;
    }
    if (_coinBusy(cl, 40)) return;

    final chain = 1 + _rng.nextInt(3);
    final high = _rng.nextDouble() < 0.12;
    for (int i = 0; i < chain; i++) {
      final z = 40.0 + i * kCoinMinGap;
      if (_coinBusy(cl, z)) break;
      if (coinList.length >= kMaxCoins) break;
      coinList.add(_Coin(lane: cl, z: z, high: high && i == chain - 1));
    }
  }

  void _frame(double dt) {
    if (dead) return;

    final target = (lane - 1).toDouble();
    final d = target - laneX;
    if (d.abs() > 0.001) {
      final step = 34 * dt * (0.48 + 0.52 * d.abs());
      laneX += d.clamp(-step, step);
    } else {
      laneX = target;
    }

    dist += speed * dt;
    worldPhase += speed * dt * 0.105;
    score = dist.toInt() + coins * 5;
    speed = min(12.8, 6.5 + dist * 0.00105);

    final cadence =
        ducking ? 2.2 : (jumpY > 0.2 || onTrain ? 1.5 : 13.5 + speed * 0.5);
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
      if (_rng.nextDouble() < 0.35) {
        _addSpark(_Spark(
          x: laneX + (_rng.nextDouble() - 0.5) * 0.15,
          z: kPlayerZ - 0.2,
          vy: 0.8 + _rng.nextDouble(),
          life: 0.25 + _rng.nextDouble() * 0.2,
          color: _rng.nextBool() ? const Color(0xFFFFEB3B) : const Color(0xFFFF6D00),
        ));
      }
    }
    if (ghost) {
      ghostT -= dt;
      if (ghostT <= 0) ghost = false;
    }

    dustAcc += dt;
    if (dustAcc > 0.055 && jumpY < 0.05 && !ducking) {
      dustAcc = 0;
      _addSpark(_Spark(
        x: laneX + (_rng.nextDouble() - 0.5) * 0.16,
        z: kPlayerZ + 0.25,
        y: 0.02,
        vy: 0.08 + _rng.nextDouble() * 0.12,
        life: 0.14 + _rng.nextDouble() * 0.1,
        color: const Color(0xFFBCAAA4),
      ));
    }

    for (final s in sparks) {
      s.life -= dt;
      s.z -= speed * dt * 0.35;
      s.y += s.vy * dt;
    }
    sparks.removeWhere((s) => s.life <= 0);

    spawnAcc += dt;
    if (spawnAcc > max(1.9, 2.8 - dist / 10000) && obs.length < kMaxObs) {
      spawnAcc = 0;
      _spawnObstacle();
    }

    coinAcc += dt;
    if (coinAcc > 0.6) {
      coinAcc = 0;
      _spawnCoins();
    }

    for (final o in obs) {
      o.z -= speed * dt * (o.stationary ? 0.26 : 1.0);
    }
    obs.removeWhere((o) => o.z + o.length < 0.1);
    for (final c in coinList) {
      c.z -= speed * dt;
    }
    coinList.removeWhere((c) => c.z < 0.1);

    if (!ghost && !jetpack && (laneX - target).abs() < 0.15) {
      for (final o in obs) {
        if (o.lane != lane) continue;
        if (kPlayerZ < o.z - 0.35 || kPlayerZ > o.z + o.length + 0.35) continue;
        switch (o.kind) {
          case 4:
            if (jumpY > 0.48 || onTrain) {
              if (!onTrain) {
                onTrain = true;
                onTrainT = 2.2;
                jumpY = 0;
                jumpV = 0;
                HapticFeedback.selectionClick();
              }
            } else {
              _die();
              return;
            }
            break;
          case 1:
          case 7:
            if (!ducking && !onTrain) {
              _die();
              return;
            }
            break;
          case 2:
            if (!onTrain) {
              _die();
              return;
            }
            break;
          default:
            if (jumpY < 0.55 && !onTrain) {
              _die();
              return;
            }
        }
      }
    }

    for (final c in coinList) {
      if (c.lane == lane && (c.z - kPlayerZ).abs() < 1.4) {
        if (c.high && jumpY < 0.2 && !onTrain) continue;
        if (!c.high && ducking) continue;
        coins++;
        c.z = -10;
        HapticFeedback.lightImpact();
        for (int i = 0; i < 4; i++) {
          _addSpark(_Spark(
            x: laneX + (_rng.nextDouble() - 0.5) * 0.2,
            z: kPlayerZ,
            vy: 0.5 + _rng.nextDouble(),
            life: 0.2 + _rng.nextDouble() * 0.2,
            color: const Color(0xFFFFD54F),
          ));
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _spawnObstacle() {
    final r = _rng.nextDouble();
    final kind = r < 0.18
        ? 0
        : r < 0.36
            ? 1
            : r < 0.48
                ? 2
                : r < 0.60
                    ? 3
                    : r < 0.70
                        ? 4
                        : r < 0.78
                            ? 5
                            : r < 0.88
                                ? 6
                                : r < 0.95
                                    ? 7
                                    : 8;

    double length = 1.0;
    if (kind == 3) length = 3.2 + _rng.nextDouble() * 1.8;
    if (kind == 4 || kind == 5 || kind == 2) length = 2.2 + _rng.nextDouble() * 1.0;
    if (kind == 6) length = 2.5;

    final isTrain = _isTrainKind(kind);
    final gap = isTrain ? kTrainMinGap : kObsMinGap;

    double z = 42.0;
    var l = _rng.nextInt(3);
    var placed = false;
    for (int attempt = 0; attempt < 12; attempt++) {
      l = (l + attempt) % 3;
      z = 42.0 + (attempt % 4) * 3.5;
      if (_laneBusy(l, z, length, gap)) continue;
      if (isTrain && _trainZoneBusy(z, length)) continue;
      placed = true;
      break;
    }
    if (!placed) return;

    obs.add(_Obs(
      lane: l,
      z: z,
      kind: kind,
      hue: _rng.nextDouble(),
      length: length,
      stationary: kind == 5,
    ));

    // Zweites Hindernis: nie Zug, nie gleiche Z-Zone wie Züge
    if (_rng.nextDouble() < 0.15 && !isTrain && obs.length < kMaxObs) {
      final l2 = (l + 1 + _rng.nextInt(2)) % 3;
      final z2 = z + kObsMinGap + 1.5;
      final len2 = kind == 3 ? 2.0 : 1.0;
      final k2 = (kind == 2 || kind == 4 || kind == 5) ? 0 : kind;
      if (!_laneBusy(l2, z2, len2, kObsMinGap) && !_trainZoneBusy(z2, len2)) {
        obs.add(_Obs(
          lane: l2,
          z: z2,
          kind: k2,
          hue: _rng.nextDouble(),
          length: len2,
        ));
      }
    }
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
      speed = 6.5;
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
                    icon: const Icon(Icons.home_rounded, color: Colors.white70, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  _chip('$score', Icons.speed_rounded),
                  const SizedBox(width: 6),
                  _chip('$coins', Icons.monetization_on_rounded, Colors.amberAccent),
                  const SizedBox(width: 6),
                  _chip('HI $high', Icons.emoji_events_rounded, Colors.orangeAccent),
                  const SizedBox(width: 6),
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
                    jumpY: jumpY + (onTrain ? 1.2 : 0),
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
                        onTrain ? '↑ Zugdach · Spur ${lane + 1}' : '←  Spur ${lane + 1} / 3  →',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(width: 14),
                      _btn(Icons.chevron_right_rounded, () => _lane(1), Colors.white),
                    ],
                  ),
                  if (dead) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: _restart,
                      style: FilledButton.styleFrom(backgroundColor: Colors.black26, foregroundColor: Colors.white),
                      child: Text(score >= high && score > 0 ? 'Play again · New high $high' : 'Play again · High $high'),
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
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.32), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
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
  double length;
  bool stationary;
  _Obs({required this.lane, required this.z, required this.kind, this.hue = 0, this.length = 1.0, this.stationary = false});
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
  _Spark({required this.x, required this.z, this.y = 0, required this.vy, required this.life, required this.color});
}

class _Cam {
  final Size size;
  final double nearY;
  final double farY;
  static const double laneSpread = 0.26;

  _Cam(this.size)
      : nearY = size.height * 0.78,
        farY = size.height * 0.30;

  Offset project(double lx, double z, [double y = 0]) {
    final t = ((z - 1.0) / 34.0).clamp(0.0, 1.0);
    final sx = size.width * 0.5 + lx * size.width * laneSpread;
    final sy = nearY + (farY - nearY) * t - y * size.height * 0.09;
    return Offset(sx, sy);
  }

  double objectSize(double z, double base) => base;
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

  static const double trackHalf = 0.135;
  static const double railGap = 0.062;

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
          colors: [Color(0xFF3A88C0), Color(0xFF6BB3E0), Color(0xFFA8D4F0), Color(0xFFC8E0A8), Color(0xFF9BCF6A)],
          stops: [0, 0.22, 0.38, 0.55, 1],
        ).createShader(Offset.zero & size),
    );

    final sunC = Offset(size.width * 0.82, size.height * 0.09);
    canvas.drawCircle(sunC, size.width * 0.05, Paint()..color = const Color(0xFFFFE082).withOpacity(0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawCircle(
      sunC,
      size.width * 0.032,
      Paint()
        ..shader = RadialGradient(colors: const [Color(0xFFFFFFEE), Color(0xFFFFEB3B), Color(0xFFFF9800)])
            .createShader(_r(sunC.dx - 24, sunC.dy - 24, 48, 48)),
    );

    final cloudShift = (worldPhase * 1.85) % (size.width * 0.4);
    for (int i = 0; i < 5; i++) {
      final cx = (size.width * (0.12 + i * 0.2) - cloudShift) % (size.width + 80) - 40;
      final cy = size.height * (0.07 + (i % 3) * 0.035);
      final p = Paint()..color = Colors.white.withOpacity(0.48);
      canvas.drawCircle(Offset(cx, cy), 14 + i * 2.0, p);
      canvas.drawCircle(Offset(cx + 16, cy + 2), 12, p);
    }

    final horizonY = cam.farY;
    final skyShift = (worldPhase * 2.9) % (size.width * 0.035);
    for (int i = -1; i < 16; i++) {
      final x = size.width * (0.012 * i) - skyShift;
      final h = size.height * (0.03 + ((i + 7) * 11 % 5) * 0.016);
      final bw = size.width * (0.024 + (i % 3) * 0.008);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, horizonY - h, bw, h), const Radius.circular(2)),
        Paint()..color = Color.lerp(const Color(0xFF2C4A5C), const Color(0xFF5A7A8C), ((i + 3) % 4) / 4)!.withOpacity(0.7),
      );
    }

    canvas.drawRect(
      _r(0, horizonY, size.width, size.height - horizonY),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFC5E06A), Color(0xFF8BC34A), Color(0xFF689F38), Color(0xFF558B2F)],
        ).createShader(_r(0, horizonY, size.width, size.height - horizonY)),
    );

    final sidePhase = worldPhase * 1.45;
    for (int i = 0; i < 10; i++) {
      final z = 6.0 + ((i * 4.5 + sidePhase) % 26);
      final left = i.isEven;
      final p = cam.project(left ? -2.2 : 2.2, z);
      final s = 24.0;
      final bh = s * (1.2 + (i % 3) * 0.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(_r(p.dx - s * 0.32, p.dy - bh, s * 0.64, bh), const Radius.circular(2)),
        Paint()..color = Color.lerp(const Color(0xFF78909C), const Color(0xFF455A64), (i % 4) / 4)!,
      );
    }
    final treePhase = worldPhase * 1.75;
    for (int i = 0; i < 14; i++) {
      final z = 4.0 + ((i * 3.6 + treePhase) % 28);
      final left = (i % 3) != 1;
      final p = cam.project(left ? -1.85 : 1.85, z);
      final s = 16.0;
      canvas.drawRect(_r(p.dx - s * 0.1, p.dy - s * 0.8, s * 0.2, s * 0.8), Paint()..color = const Color(0xFF5D4037));
      canvas.drawCircle(Offset(p.dx, p.dy - s * 0.95), s * 0.48, Paint()..color = Color.lerp(const Color(0xFF2E7D32), const Color(0xFF81C784), (i % 5) / 5)!);
    }

    final bedL = cam.project(-1.6, 1.3);
    final bedR = cam.project(1.6, 1.3);
    final bedFL = cam.project(-1.6, 32);
    final bedFR = cam.project(1.6, 32);
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
          colors: const [Color(0xFFB0B0B0), Color(0xFF8A8A8A), Color(0xFF6A6A6A), Color(0xFF555555)],
        ).createShader(Rect.fromPoints(bedL, bedFR)),
    );

    final tiePhase = (worldPhase * 2.25) % 1.5;
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
        Paint()..color = on ? const Color(0xFF6D4C41).withOpacity(0.7) : const Color(0xFF4E342E).withOpacity(0.42),
      );

      if (on) {
        final g = Path()
          ..moveTo(cam.project(lx - trackHalf * 0.26, 1.5).dx, cam.project(lx - trackHalf * 0.26, 1.5).dy)
          ..lineTo(cam.project(lx + trackHalf * 0.26, 1.5).dx, cam.project(lx + trackHalf * 0.26, 1.5).dy)
          ..lineTo(cam.project(lx + trackHalf * 0.26, 26).dx, cam.project(lx + trackHalf * 0.26, 26).dy)
          ..lineTo(cam.project(lx - trackHalf * 0.26, 26).dx, cam.project(lx - trackHalf * 0.26, 26).dy)
          ..close();
        canvas.drawPath(g, Paint()..color = const Color(0xFFFFE082).withOpacity(0.16));
      }

      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 3.2 : 2.1
        ..color = const Color(0xFF1A1A1A);
      canvas.drawLine(nearL, farL, edge);
      canvas.drawLine(nearR, farR, edge);

      for (double z = 2.0 + tiePhase; z < 30; z += 1.45) {
        final a = cam.project(lx - trackHalf * 0.92, z);
        final b = cam.project(lx + trackHalf * 0.92, z);
        canvas.drawLine(Offset(a.dx, a.dy + 1), Offset(b.dx, b.dy + 1), Paint()..color = const Color(0xFF3E2723)..strokeWidth = 4.2);
        canvas.drawLine(a, b, Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 3.5);
      }

      final pL0 = cam.project(lx - railGap, 1.35);
      final pL1 = cam.project(lx - railGap, 32);
      final pR0 = cam.project(lx + railGap, 1.35);
      final pR1 = cam.project(lx + railGap, 32);
      final metal = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = on ? 4.2 : 2.7
        ..color = on ? const Color(0xFFFAFAFA) : const Color(0xFF90A4AE);
      canvas.drawLine(pL0, pL1, metal);
      canvas.drawLine(pR0, pR1, metal);
    }

    for (final c in coins) {
      if (c.z < 1.8 || c.z > 40) continue;
      final p = cam.project((c.lane - 1).toDouble(), c.z, c.high ? 0.65 : 0.15);
      const r = 11.0;
      canvas.drawCircle(p.translate(1.2, 1.5), r, Paint()..color = Colors.black.withOpacity(0.18));
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: const [Color(0xFFFFFDE7), Color(0xFFFFEE58), Color(0xFFFFC107), Color(0xFFF57F17)],
          ).createShader(_r(p.dx - r, p.dy - r, r * 2, r * 2)),
      );
      canvas.drawCircle(p, r * 0.6, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = const Color(0xFFFFF59D));
    }

    final sorted = [...obs]..sort((a, b) => b.z.compareTo(a.z));
    for (final o in sorted) {
      if (o.z > 40) continue;
      final lx = (o.lane - 1).toDouble();
      final base = cam.project(lx, o.z);
      final w = size.width * 0.11;

      if (o.kind == 0 || o.kind == 3 || o.kind == 6 || o.kind == 8) {
        final steps = o.kind == 3 ? max(2, (o.length / 0.85).round()) : (o.kind == 6 ? 2 : 1);
        for (int i = 0; i < steps; i++) {
          final zz = o.z + i * (o.length / max(1, steps));
          if (zz < 1.8 || zz > 40) continue;
          final b = cam.project(lx, zz);
          final ww = size.width * 0.10;
          final hh = o.kind == 8 ? 28.0 : 18.0;
          final body = RRect.fromRectAndRadius(_r(b.dx - ww / 2, b.dy - hh * 0.74, ww, hh), const Radius.circular(3));
          canvas.drawRRect(
            body,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFE082), Color(0xFFFFA000), Color(0xFFE65100)],
              ).createShader(body.outerRect),
          );
        }
      } else if (o.kind == 1 || o.kind == 7) {
        const h = 48.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(_r(base.dx - w * 0.54, base.dy - h * 0.97, w, h * 0.22), const Radius.circular(3)),
          Paint()..color = const Color(0xFFFF9800),
        );
        canvas.drawRect(_r(base.dx - w * 0.5, base.dy - h * 0.84, w * 0.12, h * 0.74), Paint()..color = const Color(0xFF5D4037));
        canvas.drawRect(_r(base.dx + w * 0.38, base.dy - h * 0.84, w * 0.12, h * 0.74), Paint()..color = const Color(0xFF5D4037));
      } else {
        final steps = max(1, (o.length / 1.0).round());
        for (int i = 0; i < steps; i++) {
          final zz = o.z + i * (o.length / max(1, steps));
          if (zz < 1.8 || zz > 40) continue;
          final b = cam.project(lx, zz);
          final ww = size.width * 0.12;
          const hh = 46.0;
          final mid = o.kind == 4
              ? const Color(0xFF66BB6A)
              : o.kind == 5
                  ? const Color(0xFFFFB74D)
                  : o.hue < 0.5
                      ? const Color(0xFF26C6DA)
                      : const Color(0xFFEF5350);
          final body = RRect.fromRectAndRadius(_r(b.dx - ww / 2, b.dy - hh * 0.9, ww, hh), const Radius.circular(5));
          canvas.drawRRect(body, Paint()..color = mid);
          for (int j = 0; j < 3; j++) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                _r(b.dx - ww * 0.38 + j * ww * 0.27, b.dy - hh * 0.74, ww * 0.16, hh * 0.3),
                const Radius.circular(2),
              ),
              Paint()..color = const Color(0xFFB3E5FC).withOpacity(0.95),
            );
          }
          if (o.kind == 4) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(_r(b.dx - ww * 0.46, b.dy - hh * 1.02, ww * 0.92, 7), const Radius.circular(2)),
              Paint()..color = const Color(0xFFA5D6A7),
            );
          }
          canvas.drawCircle(Offset(b.dx - ww * 0.28, b.dy - hh * 0.08), ww * 0.08, Paint()..color = const Color(0xFF37474F));
          canvas.drawCircle(Offset(b.dx + ww * 0.28, b.dy - hh * 0.08), ww * 0.08, Paint()..color = const Color(0xFF37474F));
        }
      }
    }

    for (final s in sparks) {
      if (s.z < 1.5 || s.z > 20) continue;
      final p = cam.project(s.x, s.z, s.y);
      final a = (s.life * 2).clamp(0.0, 1.0);
      canvas.drawCircle(p, 2.2 + s.life * 2.8, Paint()..color = s.color.withOpacity(0.65 * a));
    }

    final feet = cam.project(laneX, 3.0, 0);
    final body = cam.project(laneX, 3.0, jumpY + (jetpack ? 1.1 : 0));
    _runner(canvas, Offset(body.dx, body.dy), feet.dy, 1.58, runPhase, ducking, jumpY > 0.12 || onTrain, ghost, jetpack);

    if (dead) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.42));
    }
  }

  /// Sprung: Beine anziehen (nicht länger werden), Landen: wieder strecken
  void _runner(Canvas c, Offset pos, double groundY, double scale, double phase, bool duck, bool air, bool ghost, bool jet) {
    final s = 34.0 * scale;
    final skin = ghost ? Colors.purpleAccent.withOpacity(0.9) : const Color(0xFFFFCC80);
    final shirt = ghost ? Colors.deepPurple : const Color(0xFF1E88E5);
    final pants = ghost ? Colors.deepPurple.shade800 : const Color(0xFF1565C0);

    final legPhase = sin(phase);
    final legPhase2 = sin(phase + pi);
    final armPhase = sin(phase + pi);

    final legAmp = duck ? 0.06 : (air ? 0.0 : 1.2);
    final armAmp = duck ? 0.05 : (air ? 0.15 : 1.1);
    final bob = duck || air ? 0.0 : ((1 - cos(phase * 2)) * 0.5) * s * 0.22;
    final lean = air ? -0.04 : (duck ? 0.1 : 0.05);

    // Schatten nur am Boden wenn nicht in der Luft
    if (!air) {
      c.drawOval(_r(pos.dx - s * 0.42, groundY + s * 0.04, s * 0.84, 8), Paint()..color = Colors.black.withOpacity(0.32));
    } else {
      c.drawOval(_r(pos.dx - s * 0.28, groundY + s * 0.04, s * 0.56, 6), Paint()..color = Colors.black.withOpacity(0.18));
    }

    final bodyTop = (duck ? pos.dy + s * 0.14 : pos.dy - s * 0.28) + bob;
    final bodyH = duck ? s * 0.4 : s * 1.12;
    final hip = Offset(pos.dx + lean * s * 0.25, bodyTop + bodyH * 0.58);

    final lp = Paint()..color = pants..strokeWidth = s * 0.33..strokeCap = StrokeCap.round;

    late Offset leftFoot;
    late Offset rightFoot;
    late Offset leftKnee;
    late Offset rightKnee;

    if (air) {
      // Beine angezogen unter dem Körper – feste Länge, kein Stretch zum Boden
      final tuck = s * 0.42;
      leftKnee = Offset(hip.dx - s * 0.18, hip.dy + s * 0.22);
      rightKnee = Offset(hip.dx + s * 0.18, hip.dy + s * 0.22);
      leftFoot = Offset(leftKnee.dx - s * 0.08, leftKnee.dy + tuck);
      rightFoot = Offset(rightKnee.dx + s * 0.08, rightKnee.dy + tuck);
    } else {
      final leftLift = (!duck && legPhase > 0) ? legPhase * s * 0.1 : 0.0;
      final rightLift = (!duck && legPhase2 > 0) ? legPhase2 * s * 0.1 : 0.0;
      leftFoot = Offset(pos.dx - s * 0.28 - legPhase * s * 0.6 * legAmp, groundY - leftLift);
      rightFoot = Offset(pos.dx + s * 0.28 - legPhase2 * s * 0.6 * legAmp, groundY - rightLift);
      leftKnee = Offset(
        (hip.dx + leftFoot.dx) * 0.5 - s * 0.06,
        (hip.dy + leftFoot.dy) * 0.48 - (duck ? 0 : s * 0.1 * (1 - legPhase.abs().clamp(0.0, 1.0))),
      );
      rightKnee = Offset(
        (hip.dx + rightFoot.dx) * 0.5 + s * 0.06,
        (hip.dy + rightFoot.dy) * 0.48 - (duck ? 0 : s * 0.1 * (1 - legPhase2.abs().clamp(0.0, 1.0))),
      );
    }

    c.drawLine(hip, leftKnee, lp);
    c.drawLine(leftKnee, leftFoot, lp);
    c.drawLine(hip, rightKnee, lp);
    c.drawLine(rightKnee, rightFoot, lp);

    c.drawRRect(RRect.fromRectAndRadius(_r(leftFoot.dx - s * 0.17, leftFoot.dy - s * 0.06, s * 0.34, s * 0.14), Radius.circular(s * 0.05)), Paint()..color = const Color(0xFF212121));
    c.drawRRect(RRect.fromRectAndRadius(_r(rightFoot.dx - s * 0.17, rightFoot.dy - s * 0.06, s * 0.34, s * 0.14), Radius.circular(s * 0.05)), Paint()..color = const Color(0xFF212121));

    final bodyRect = RRect.fromRectAndRadius(
      _r(pos.dx - s * 0.32 + lean * s * 0.15, bodyTop, s * 0.64, bodyH),
      Radius.circular(s * 0.16),
    );
    c.drawRRect(
      bodyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [shirt.withOpacity(0.95), shirt, pants],
        ).createShader(bodyRect.outerRect),
    );

    final sh = Offset(pos.dx + lean * s * 0.12, bodyTop + bodyH * 0.12);
    final ap = Paint()..color = shirt..strokeWidth = s * 0.23..strokeCap = StrokeCap.round;
    final leftHand = Offset(pos.dx - s * 0.55, sh.dy + s * 0.45 + armPhase * s * 0.52 * armAmp);
    final rightHand = Offset(pos.dx + s * 0.55, sh.dy + s * 0.45 - armPhase * s * 0.52 * armAmp);
    c.drawLine(sh, leftHand, ap);
    c.drawLine(sh, rightHand, ap);

    final headY = bodyTop - s * 0.35;
    final hr = s * 0.37;
    final hx = pos.dx + lean * s * 0.08;
    c.drawCircle(
      Offset(hx, headY),
      hr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.3),
          colors: [Colors.white.withOpacity(0.9), skin, const Color(0xFFE0A060)],
        ).createShader(_r(hx - hr, headY - hr, hr * 2, hr * 2)),
    );
    c.drawCircle(Offset(hx - hr * 0.3, headY - hr * 0.05), hr * 0.13, Paint()..color = Colors.white);
    c.drawCircle(Offset(hx + hr * 0.3, headY - hr * 0.05), hr * 0.13, Paint()..color = Colors.white);
    c.drawCircle(Offset(hx - hr * 0.3, headY - hr * 0.05), hr * 0.065, Paint()..color = const Color(0xFF1A237E));
    c.drawCircle(Offset(hx + hr * 0.3, headY - hr * 0.05), hr * 0.065, Paint()..color = const Color(0xFF1A237E));
    c.drawArc(
      _r(hx - hr, headY - hr * 1.05, hr * 2, hr * 1.15),
      3.4,
      2.5,
      false,
      Paint()
        ..color = const Color(0xFF3E2723)
        ..style = PaintingStyle.stroke
        ..strokeWidth = hr * 0.36
        ..strokeCap = StrokeCap.round,
    );

    if (jet) {
      final jr = 13.0;
      c.drawCircle(
        Offset(pos.dx, pos.dy + s * 0.95),
        jr,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xFFFFFF00), Color(0xFFFF6D00), Colors.transparent])
              .createShader(_r(pos.dx - jr, pos.dy + s * 0.95 - jr, jr * 2, jr * 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunPainter old) => true;
}
