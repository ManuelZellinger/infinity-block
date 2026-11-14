import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Infinity Run - 3-lane endless runner (Subway Surfers style)
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
  double speed = 7.0;
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

  static const double jumpPower = 15.5;
  static const double gravity = 38.0;
  static const double kPlayerZ = 2.8;
  static const double duckDuration = 1.6;
  static const double kCoinMinGap = 2.6;
  static const double kObsMinGap = 10.0;
  static const double kTrainMinGap = 18.0;
  static const int kMaxObs = 12;
  static const int kMaxCoins = 20;
  static const int kMaxSparks = 48;

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
    _frame(dt.clamp(0.0, 0.04));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  bool _isTrain(int k) => k == 2 || k == 4 || k == 5;

  bool _laneBusy(int l, double z, double len, double gap) {
    for (final o in obs) {
      if (o.lane != l) continue;
      if (z < o.z + o.length + gap && z + len + gap > o.z) return true;
    }
    return false;
  }

  bool _trainZoneBusy(double z, double len) {
    for (final o in obs) {
      if (!_isTrain(o.kind)) continue;
      if (z < o.z + o.length + kTrainMinGap &&
          z + len + kTrainMinGap > o.z) {
        return true;
      }
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
    for (int t = 0; t < 3; t++) {
      if (!_coinBusy(cl, 26)) break;
      cl = (cl + 1) % 3;
    }
    if (_coinBusy(cl, 26)) return;
    final n = 1 + _rng.nextInt(3);
    final highC = _rng.nextDouble() < 0.15;
    for (int i = 0; i < n; i++) {
      final z = 26.0 + i * kCoinMinGap;
      if (_coinBusy(cl, z) || coinList.length >= kMaxCoins) break;
      coinList.add(_Coin(lane: cl, z: z, high: highC && i == n - 1));
    }
  }

  void _spawnObstacle() {
    final r = _rng.nextDouble();
    final kind = r < 0.16
        ? 0
        : r < 0.30
            ? 1
            : r < 0.42
                ? 2
                : r < 0.54
                    ? 3
                    : r < 0.66
                        ? 4
                        : r < 0.74
                            ? 5
                            : r < 0.84
                                ? 6
                                : r < 0.92
                                    ? 7
                                    : 8;

    double length = 1.0;
    if (kind == 3) length = 3.0 + _rng.nextDouble() * 1.5;
    if (kind == 2 || kind == 4 || kind == 5) {
      length = 3.2 + _rng.nextDouble() * 1.4;
    }
    if (kind == 6) length = 2.2;

    final isTrain = _isTrain(kind);
    final gap = isTrain ? kTrainMinGap : kObsMinGap;
    var l = _rng.nextInt(3);
    var z = 28.0;
    var placed = false;
    for (int a = 0; a < 14; a++) {
      l = (l + a) % 3;
      z = 28.0 + (a % 5) * 2.5;
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
  }

  void _frame(double dt) {
    if (dead) return;

    final target = (lane - 1).toDouble();
    final d = target - laneX;
    if (d.abs() > 0.002) {
      final step = 28 * dt * (0.5 + 0.5 * d.abs());
      laneX += d.clamp(-step, step);
    } else {
      laneX = target;
    }

    dist += speed * dt;
    worldPhase += speed * dt * 0.28;
    score = dist.toInt() + coins * 5;
    speed = min(13.5, 7.0 + dist * 0.0011);

    final cadence = ducking
        ? 3.2
        : (jumpY > 0.15 ? 2.2 : 12.0 + speed * 0.5);
    runPhase += dt * cadence;

    if (jumpY > 0 || jumpV != 0) {
      jumpV -= gravity * dt;
      jumpY += jumpV * dt;
      if (jumpY <= 0) {
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
      if (onTrainT <= 0 || jumpY > 0.08) {
        onTrain = false;
        onTrainT = 0;
      }
    }
    if (jetpack) {
      jetpackT -= dt;
      if (jetpackT <= 0) jetpack = false;
    }
    if (ghost) {
      ghostT -= dt;
      if (ghostT <= 0) ghost = false;
    }

    for (final s in sparks) {
      s.life -= dt;
      s.z -= speed * dt * 0.4;
      s.y += s.vy * dt;
    }
    sparks.removeWhere((s) => s.life <= 0);

    spawnAcc += dt;
    if (spawnAcc > max(1.9, 2.7 - dist / 9000) && obs.length < kMaxObs) {
      spawnAcc = 0;
      _spawnObstacle();
    }
    coinAcc += dt;
    if (coinAcc > 0.55) {
      coinAcc = 0;
      _spawnCoins();
    }

    for (final o in obs) {
      o.z -= speed * dt * (o.stationary ? 0.22 : 1.0);
    }
    obs.removeWhere((o) => o.z + o.length < 1.0);
    for (final c in coinList) {
      c.z -= speed * dt;
    }
    coinList.removeWhere((c) => c.z < 1.0);

    if (!ghost && !jetpack && (laneX - target).abs() < 0.18) {
      for (final o in obs) {
        if (o.lane != lane) continue;
        if (kPlayerZ < o.z - 0.4 || kPlayerZ > o.z + o.length + 0.4) {
          continue;
        }
        switch (o.kind) {
          case 4:
            if (jumpY > 0.45 || onTrain) {
              if (!onTrain) {
                onTrain = true;
                onTrainT = 2.0;
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
            if (jumpY < 0.5 && !onTrain) {
              _die();
              return;
            }
        }
      }
    }

    for (final c in coinList) {
      if (c.lane == lane && (c.z - kPlayerZ).abs() < 1.35) {
        if (c.high && jumpY < 0.25 && !onTrain) continue;
        if (!c.high && ducking) continue;
        coins++;
        c.z = -20;
        HapticFeedback.lightImpact();
        for (int i = 0; i < 5; i++) {
          sparks.add(_Spark(
            x: laneX + (_rng.nextDouble() - 0.5) * 0.2,
            z: kPlayerZ,
            vy: 0.6 + _rng.nextDouble(),
            life: 0.25 + _rng.nextDouble() * 0.2,
            color: const Color(0xFFFFD54F),
          ));
          if (sparks.length > kMaxSparks) sparks.removeAt(0);
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
      speed = 7.0;
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
    if (jumpY > 0.1 && !onTrain) return;
    setState(() {
      jumpV = jumpPower;
      onTrain = false;
    });
    HapticFeedback.mediumImpact();
  }

  void _duck() {
    if (dead || !mounted || jumpY > 0.3 || onTrain) return;
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
      jumpY = 2.2;
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
              child: Row(children: [
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
              ]),
            ),
            Expanded(
              child: ExcludeSemantics(
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
                    if (_panX.abs() > 14 &&
                        _panX.abs() > _panY.abs() * 1.1) {
                      _panUsed = true;
                      _lane(_panX < 0 ? -1 : 1);
                    } else if (_panY < -16 &&
                        _panY.abs() > _panX.abs()) {
                      _panUsed = true;
                      _jump();
                    } else if (_panY > 16 &&
                        _panY.abs() > _panX.abs()) {
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
                ]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _btn(Icons.chevron_left_rounded, () => _lane(-1),
                      Colors.white),
                  const SizedBox(width: 14),
                  Text(
                    onTrain
                        ? 'Zugdach · Spur ${lane + 1}'
                        : '←  Spur ${lane + 1} / 3  →',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
                  const SizedBox(width: 14),
                  _btn(Icons.chevron_right_rounded, () => _lane(1),
                      Colors.white),
                ]),
                if (dead) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _restart,
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.black26,
                        foregroundColor: Colors.white),
                    child: Text(score >= high && score > 0
                        ? 'Play again · New high $high'
                        : 'Play again · High $high'),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String v, IconData icon, [Color c = Colors.white]) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.32),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(v,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );

  Widget _btn(IconData icon, VoidCallback on, Color c) => Material(
        color: Colors.black.withOpacity(0.36),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
            onTap: on,
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
                width: 54, height: 46, child: Icon(icon, color: c, size: 28))),
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
  final double nearY;
  final double farY;
  static const double laneSpreadNear = 0.28;
  static const double laneSpreadFar = 0.10;

  _Cam(this.size)
      : nearY = size.height * 0.88,
        farY = size.height * 0.22;

  Offset project(double lx, double z, [double y = 0]) {
    final t = ((z - 1.0) / 26.0).clamp(0.0, 1.0);
    final tVis = t * t * 0.35 + t * 0.65;
    final spread =
        laneSpreadNear + (laneSpreadFar - laneSpreadNear) * tVis;
    final sx = size.width * 0.5 + lx * size.width * spread;
    final sy = nearY + (farY - nearY) * tVis - y * size.height * 0.12;
    return Offset(sx, sy);
  }

  double scaleAt(double z) {
    final t = ((z - 1.0) / 26.0).clamp(0.0, 1.0);
    return 1.0 - t * 0.55;
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
            Color(0xFF1E6FA8),
            Color(0xFF4A9BC7),
            Color(0xFF8EC8E8),
            Color(0xFFB5D9EF),
          ],
          stops: [0, 0.35, 0.72, 1],
        ).createShader(Offset.zero & size),
    );

    final sun = Offset(size.width * 0.82, size.height * 0.10);
    canvas.drawCircle(
      sun,
      size.width * 0.045,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFFFFF59D), Color(0xFFFFC107), Color(0x00FFC107)],
        ).createShader(_r(sun.dx - 40, sun.dy - 40, 80, 80)),
    );

    final horizonY = cam.farY;
    final leftEdge = cam.project(-1.7, 1.2).dx;
    final rightEdge = cam.project(1.7, 1.2).dx;
    final grassShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFF7CB342), Color(0xFF558B2F), Color(0xFF33691E)],
    ).createShader(_r(0, horizonY, size.width, size.height - horizonY));
    canvas.drawRect(
        _r(0, horizonY, leftEdge.clamp(0, size.width), size.height - horizonY),
        Paint()..shader = grassShader);
    canvas.drawRect(
        _r(rightEdge.clamp(0, size.width), horizonY,
            size.width - rightEdge.clamp(0, size.width), size.height - horizonY),
        Paint()..shader = grassShader);

    final bedPath = Path()
      ..moveTo(cam.project(-1.55, 1.0).dx, cam.project(-1.55, 1.0).dy)
      ..lineTo(cam.project(1.55, 1.0).dx, cam.project(1.55, 1.0).dy)
      ..lineTo(cam.project(1.55, 26).dx, cam.project(1.55, 26).dy)
      ..lineTo(cam.project(-1.55, 26).dx, cam.project(-1.55, 26).dy)
      ..close();
    canvas.drawPath(bedPath, Paint()..color = const Color(0xFF7A7A7A));

    final tiePhase = worldPhase % 1.0;
    for (int l = 0; l < 3; l++) {
      final lx = (l - 1).toDouble();
      final on = l == activeLane;
      final half = 0.13;
      final nearL = cam.project(lx - half, 1.0);
      final nearR = cam.project(lx + half, 1.0);
      final farL = cam.project(lx - half, 26);
      final farR = cam.project(lx + half, 26);
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
              ? const Color(0xFF5D4037).withOpacity(0.85)
              : const Color(0xFF3E2723).withOpacity(0.55),
      );

      for (double z = 1.2 + tiePhase; z < 25; z += 0.95) {
        final a = cam.project(lx - half * 0.9, z);
        final b = cam.project(lx + half * 0.9, z);
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF8D6E63)
            ..strokeWidth = 3.2 * cam.scaleAt(z)
            ..strokeCap = StrokeCap.round,
        );
      }

      final railW = on ? 3.8 : 2.6;
      final railColor =
          on ? const Color(0xFFF5F5F5) : const Color(0xFF90A4AE);
      final rp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = railW
        ..strokeCap = StrokeCap.round
        ..color = railColor;
      canvas.drawLine(
          cam.project(lx - 0.055, 1.0), cam.project(lx - 0.055, 26), rp);
      canvas.drawLine(
          cam.project(lx + 0.055, 1.0), cam.project(lx + 0.055, 26), rp);
    }

    for (final c in coins) {
      if (c.z < 1.2 || c.z > 25) continue;
      final sc = cam.scaleAt(c.z);
      final p = cam.project(
          (c.lane - 1).toDouble(), c.z, c.high ? 0.7 : 0.18);
      final r = 11.0 * sc + 2.0;
      canvas.drawOval(
        _r(p.dx - r * 0.8, p.dy + r * 0.5, r * 1.6, r * 0.4),
        Paint()..color = Colors.black.withOpacity(0.25),
      );
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.4),
            radius: 1.05,
            colors: const [
              Color(0xFFFFF8E1),
              Color(0xFFFFE082),
              Color(0xFFFFC107),
              Color(0xFFFF8F00),
              Color(0xFFE65100),
            ],
            stops: const [0, 0.22, 0.5, 0.78, 1],
          ).createShader(_r(p.dx - r, p.dy - r, r * 2, r * 2)),
      );
      canvas.drawCircle(
        p,
        r * 0.9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12
          ..color = const Color(0xFFBF360C).withOpacity(0.55),
      );
      final ir = r * 0.4;
      final star = Path();
      for (int i = 0; i < 5; i++) {
        final a = -pi / 2 + i * 2 * pi / 5;
        final a2 = a + pi / 5;
        final ox = p.dx + cos(a) * ir;
        final oy = p.dy + sin(a) * ir;
        final ix = p.dx + cos(a2) * ir * 0.4;
        final iy = p.dy + sin(a2) * ir * 0.4;
        if (i == 0) {
          star.moveTo(ox, oy);
        } else {
          star.lineTo(ox, oy);
        }
        star.lineTo(ix, iy);
      }
      star.close();
      canvas.drawPath(
        star,
        Paint()
          ..shader = RadialGradient(
            colors: const [Color(0xFFFFFDE7), Color(0xFFFFB300)],
          ).createShader(_r(p.dx - ir, p.dy - ir, ir * 2, ir * 2)),
      );
      canvas.drawOval(
        _r(p.dx - r * 0.55, p.dy - r * 0.55, r * 0.5, r * 0.32),
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withOpacity(0.8),
              Colors.white.withOpacity(0.0),
            ],
          ).createShader(
              _r(p.dx - r * 0.55, p.dy - r * 0.55, r * 0.5, r * 0.32)),
      );
    }

    final sorted = [...obs]..sort((a, b) => b.z.compareTo(a.z));
    for (final o in sorted) {
      if (o.z > 25 || o.z + o.length < 1.2) continue;
      final lx = (o.lane - 1).toDouble();
      final sc = cam.scaleAt(o.z);
      final base = cam.project(lx, o.z);
      final w = size.width * 0.10 * sc;

      if (o.kind == 0 || o.kind == 3 || o.kind == 6 || o.kind == 8) {
        final steps =
            o.kind == 3 ? max(2, (o.length / 0.9).round()) : (o.kind == 6 ? 2 : 1);
        for (int i = 0; i < steps; i++) {
          final zz = o.z + i * (o.length / max(1, steps));
          if (zz < 1.2 || zz > 25) continue;
          final b = cam.project(lx, zz);
          final ww = size.width * 0.09 * cam.scaleAt(zz);
          final hh = (o.kind == 8 ? 26.0 : 16.0) * cam.scaleAt(zz);
          canvas.drawOval(
            _r(b.dx - ww * 0.5, b.dy + hh * 0.05, ww, 7),
            Paint()..color = Colors.black.withOpacity(0.22),
          );
          final body = RRect.fromRectAndRadius(
            _r(b.dx - ww / 2, b.dy - hh * 0.75, ww, hh),
            const Radius.circular(3),
          );
          canvas.drawRRect(
            body,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFE082),
                  Color(0xFFFFB300),
                  Color(0xFFFF6F00),
                  Color(0xFFE65100),
                ],
              ).createShader(body.outerRect),
          );
        }
      } else if (o.kind == 1 || o.kind == 7) {
        final h = 44.0 * sc;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            _r(base.dx - w * 0.55, base.dy - h * 0.95, w * 1.1, h * 0.2),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFFFF9800),
        );
        canvas.drawRect(
          _r(base.dx - w * 0.5, base.dy - h * 0.82, w * 0.12, h * 0.7),
          Paint()..color = const Color(0xFF5D4037),
        );
        canvas.drawRect(
          _r(base.dx + w * 0.38, base.dy - h * 0.82, w * 0.12, h * 0.7),
          Paint()..color = const Color(0xFF5D4037),
        );
      } else {
        final mid = o.kind == 4
            ? const Color(0xFF43A047)
            : o.kind == 5
                ? const Color(0xFFFFA726)
                : o.hue < 0.5
                    ? const Color(0xFF00ACC1)
                    : const Color(0xFFE53935);
        final dark = Color.lerp(mid, Colors.black, 0.35)!;
        final cars = max(2, (o.length / 1.1).round());
        for (int i = 0; i < cars; i++) {
          final zz = o.z + i * (o.length / cars);
          if (zz < 1.2 || zz > 25) continue;
          final b = cam.project(lx, zz);
          final s2 = cam.scaleAt(zz);
          final ww = size.width * 0.072 * s2;
          final hh = 36.0 * s2;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              _r(b.dx - ww * 0.52, b.dy - hh * 0.1, ww * 1.04, hh * 0.12),
              const Radius.circular(2),
            ),
            Paint()..color = const Color(0xFF37474F),
          );
          canvas.drawCircle(Offset(b.dx - ww * 0.3, b.dy), ww * 0.11,
              Paint()..color = const Color(0xFF212121));
          canvas.drawCircle(Offset(b.dx + ww * 0.3, b.dy), ww * 0.11,
              Paint()..color = const Color(0xFF212121));
          final body = RRect.fromRectAndRadius(
            _r(b.dx - ww / 2, b.dy - hh * 0.9, ww, hh * 0.8),
            const Radius.circular(4),
          );
          canvas.drawRRect(
            body,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(mid, Colors.white, 0.18)!,
                  mid,
                  dark,
                ],
              ).createShader(body.outerRect),
          );
          for (int j = 0; j < 2; j++) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                _r(b.dx - ww * 0.36 + j * ww * 0.4, b.dy - hh * 0.7,
                    ww * 0.3, hh * 0.26),
                const Radius.circular(2),
              ),
              Paint()..color = const Color(0xFFB3E5FC).withOpacity(0.95),
            );
          }
          if (o.kind == 4) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                _r(b.dx - ww * 0.4, b.dy - hh * 1.02, ww * 0.8, 5 * s2),
                const Radius.circular(2),
              ),
              Paint()..color = const Color(0xFFA5D6A7),
            );
          }
        }
      }
    }

    for (final s in sparks) {
      if (s.z < 1.2 || s.z > 18) continue;
      final p = cam.project(s.x, s.z, s.y);
      final a = (s.life * 2).clamp(0.0, 1.0);
      canvas.drawCircle(
        p,
        2.0 + s.life * 2.5,
        Paint()..color = s.color.withOpacity(0.65 * a),
      );
    }

    final feet = cam.project(laneX, kPlayerZ, 0);
    final body = cam.project(laneX, kPlayerZ, jumpY + (jetpack ? 1.0 : 0));
    _drawRunner(
      canvas,
      Offset(body.dx, body.dy),
      feet.dy,
      1.5,
      runPhase,
      ducking,
      jumpY > 0.2,
      ghost,
      jetpack,
      jumpY,
    );

    if (dead) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withOpacity(0.4),
      );
    }
  }

  void _drawRunner(
    Canvas c,
    Offset pos,
    double groundY,
    double scale,
    double phase,
    bool duck,
    bool air,
    bool ghost,
    bool jet,
    double jumpAmt,
  ) {
    final s = 30.0 * scale;
    final skin =
        ghost ? Colors.purpleAccent.withOpacity(0.9) : const Color(0xFFFFCC80);
    final shirt = ghost ? Colors.deepPurple : const Color(0xFF1565C0);
    final pants =
        ghost ? Colors.deepPurple.shade800 : const Color(0xFF0D47A1);
    const shoe = Color(0xFF1A1A1A);

    final thighLen = s * 0.42;
    final shinLen = s * 0.40;
    final upperArm = s * 0.32;
    final foreArm = s * 0.28;

    final bob = (!air && !duck)
        ? (1 - cos(phase * 2)) * 0.5 * s * 0.14
        : 0.0;
    final lean = air ? -0.08 : (duck ? 0.14 : 0.04);

    if (!air) {
      c.drawOval(
        _r(pos.dx - s * 0.38, groundY + 1, s * 0.76, 6),
        Paint()..color = Colors.black.withOpacity(0.28),
      );
    }

    final bodyTop = (duck ? pos.dy + s * 0.18 : pos.dy - s * 0.22) + bob;
    final bodyH = duck ? s * 0.36 : s * 0.95;
    final hipY = bodyTop + bodyH * 0.62;
    final hip = Offset(pos.dx + lean * s * 0.15, hipY);
    final shoulder = Offset(pos.dx + lean * s * 0.08, bodyTop + bodyH * 0.12);

    late Offset kneeL, kneeR, footL, footR;

    if (air) {
      final tuck = (jumpAmt / 2.0).clamp(0.0, 1.0);
      kneeL = Offset(hip.dx - s * 0.14, hip.dy + s * 0.14);
      kneeR = Offset(hip.dx + s * 0.14, hip.dy + s * 0.14);
      footL = Offset(kneeL.dx - s * 0.02, kneeL.dy + shinLen * (0.5 + 0.25 * (1 - tuck)));
      footR = Offset(kneeR.dx + s * 0.02, kneeR.dy + shinLen * (0.5 + 0.25 * (1 - tuck)));
    } else if (duck) {
      kneeL = Offset(hip.dx - s * 0.16, hip.dy + s * 0.18);
      kneeR = Offset(hip.dx + s * 0.16, hip.dy + s * 0.18);
      footL = Offset(hip.dx - s * 0.22, groundY);
      footR = Offset(hip.dx + s * 0.22, groundY);
    } else {
      void placeLeg(double p, bool left) {
        final side = left ? -1.0 : 1.0;
        final swing = sin(p);
        final stance = cos(p);
        final kneeX = hip.dx + side * s * 0.10 + swing * s * 0.22;
        final kneeY = hip.dy + thighLen * 0.92 - max(0.0, -stance) * s * 0.10;
        final knee = Offset(kneeX, kneeY);
        double footX = knee.dx + side * s * 0.04 + swing * s * 0.18;
        double footY;
        if (stance > 0.05) {
          footY = groundY;
          footX = hip.dx + side * s * 0.08 + swing * s * 0.12;
        } else {
          final lift = (-stance).clamp(0.0, 1.0) * s * 0.22;
          footY = groundY - lift;
        }
        final dx = footX - knee.dx;
        final dy = footY - knee.dy;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > shinLen * 1.15 && dist > 0.001) {
          final k = shinLen * 1.05 / dist;
          footX = knee.dx + dx * k;
          footY = knee.dy + dy * k;
          if (stance > 0.05) footY = groundY;
        }
        if (left) {
          kneeL = knee;
          footL = Offset(footX, footY);
        } else {
          kneeR = knee;
          footR = Offset(footX, footY);
        }
      }

      placeLeg(phase, true);
      placeLeg(phase + pi, false);
    }

    final legPaint = Paint()
      ..color = pants
      ..strokeWidth = s * 0.28
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    c.drawLine(hip, kneeL, legPaint);
    c.drawLine(kneeL, footL, legPaint);
    c.drawLine(hip, kneeR, legPaint);
    c.drawLine(kneeR, footR, legPaint);
    c.drawCircle(kneeL, s * 0.09, Paint()..color = pants);
    c.drawCircle(kneeR, s * 0.09, Paint()..color = pants);

    void drawShoe(Offset foot, double side) {
      final rect = RRect.fromRectAndRadius(
        _r(foot.dx - s * 0.14 + side * s * 0.02, foot.dy - s * 0.04, s * 0.30, s * 0.11),
        Radius.circular(s * 0.04),
      );
      c.drawRRect(rect, Paint()..color = shoe);
      c.drawLine(
        Offset(foot.dx - s * 0.06, foot.dy + s * 0.02),
        Offset(foot.dx + s * 0.12, foot.dy + s * 0.02),
        Paint()
          ..color = const Color(0xFFFF5722)
          ..strokeWidth = 1.8,
      );
    }

    drawShoe(footL, -1);
    drawShoe(footR, 1);

    c.drawRRect(
      RRect.fromRectAndRadius(
        _r(pos.dx - s * 0.13 + lean * s * 0.1, bodyTop + bodyH * 0.08,
            s * 0.26, bodyH * 0.34),
        Radius.circular(s * 0.05),
      ),
      Paint()..color = const Color(0xFFE53935),
    );

    final bodyRect = RRect.fromRectAndRadius(
      _r(pos.dx - s * 0.26 + lean * s * 0.1, bodyTop, s * 0.52, bodyH),
      Radius.circular(s * 0.13),
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

    final armPaint = Paint()
      ..color = shirt
      ..strokeWidth = s * 0.20
      ..strokeCap = StrokeCap.round;

    void placeArm(double p, bool left) {
      final side = left ? -1.0 : 1.0;
      final swingA = air ? 0.15 : (duck ? 0.08 : sin(p));
      final elbowBend = air ? 0.9 : 0.45 + max(0.0, -sin(p)) * 0.4;
      final elbow = Offset(
        shoulder.dx + side * (upperArm * 0.55 + swingA * s * 0.12),
        shoulder.dy + upperArm * 0.75 + (air ? s * 0.05 : 0),
      );
      final hand = Offset(
        elbow.dx + side * (foreArm * 0.35 + swingA * s * 0.2),
        elbow.dy + foreArm * (0.7 - elbowBend * 0.2) + swingA * s * 0.25,
      );
      c.drawLine(shoulder, elbow, armPaint);
      c.drawLine(elbow, hand, armPaint);
      c.drawCircle(elbow, s * 0.07, Paint()..color = shirt);
      c.drawCircle(hand, s * 0.09, Paint()..color = skin);
    }

    placeArm(phase + pi, true);
    placeArm(phase, false);

    final headY = bodyTop - s * 0.28;
    final hr = s * 0.32;
    final hx = pos.dx + lean * s * 0.05;
    c.drawCircle(
      Offset(hx, headY),
      hr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.3),
          colors: [
            Colors.white.withOpacity(0.9),
            skin,
            const Color(0xFFE0A060),
          ],
        ).createShader(_r(hx - hr, headY - hr, hr * 2, hr * 2)),
    );
    c.drawCircle(Offset(hx - hr * 0.24, headY - hr * 0.02), hr * 0.11,
        Paint()..color = Colors.white);
    c.drawCircle(Offset(hx + hr * 0.24, headY - hr * 0.02), hr * 0.11,
        Paint()..color = Colors.white);
    c.drawCircle(Offset(hx - hr * 0.24, headY - hr * 0.02), hr * 0.05,
        Paint()..color = const Color(0xFF1A237E));
    c.drawCircle(Offset(hx + hr * 0.24, headY - hr * 0.02), hr * 0.05,
        Paint()..color = const Color(0xFF1A237E));

    final cap = Path()
      ..moveTo(hx - hr * 0.95, headY - hr * 0.08)
      ..quadraticBezierTo(hx, headY - hr * 1.15, hx + hr * 0.95, headY - hr * 0.08)
      ..lineTo(hx + hr * 1.05, headY + hr * 0.05)
      ..quadraticBezierTo(hx, headY - hr * 0.4, hx - hr * 1.05, headY + hr * 0.05)
      ..close();
    c.drawPath(cap, Paint()..color = const Color(0xFFE53935));

    if (jet) {
      final jr = 11.0;
      c.drawCircle(
        Offset(pos.dx, pos.dy + s * 0.85),
        jr,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFFFF00), Color(0xFFFF6D00), Colors.transparent],
          ).createShader(
              _r(pos.dx - jr, pos.dy + s * 0.85 - jr, jr * 2, jr * 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunPainter old) => true;
}
