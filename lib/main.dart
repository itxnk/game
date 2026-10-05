import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Allow the game to rotate with the phone in portrait or landscape.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: RaceGame()));
}

enum Phase { menu, playing, over }

class Traffic {
  double x, z, speed;
  // Position at the previous frame, used for swept collision checks.
  double prevZ;
  final Color color;
  bool passed = false;
  Traffic(this.x, this.z, this.speed, this.color) : prevZ = z;
}

class RaceGame extends StatefulWidget {
  const RaceGame({super.key});
  @override
  State<RaceGame> createState() => _RaceGameState();
}

class _RaceGameState extends State<RaceGame> with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  Duration last = Duration.zero;
  final rnd = Random();
  Size size = Size.zero;

  Phase phase = Phase.menu;
  // World units: road is 4 units wide (4 lanes), x in [-2, 2]. Speed in units/s.
  double x = 0, v = 0, steer = 0, dist = 0, nitro = 100, shake = 0, spawnT = 0;
  int bonus = 0, best = 0;
  bool useNos = false, braking = false;
  List<Traffic> cars = [];

  // touch state
  bool tL = false, tR = false, tGas = false, tBrk = false, tNos = false;
  double? dragStartX;
  double dragSteer = 0;

  static const colors = [
    Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFFFB8C00),
    Color(0xFF8E24AA), Color(0xFFFDD835), Color(0xFF90A4AE), Color(0xFFF5F5F5),
  ];

  int get score => dist ~/ 10 + bonus;
  double roadW(Size s) => min(s.width * 0.92, 520.0);

  @override
  void initState() {
    super.initState();
    ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  void start() {
    // Start at a useful driving speed instead of slowly building up from a crawl.
    x = 0; v = 5; steer = 0; dist = 0; nitro = 100; bonus = 0; spawnT = 1.2;
    shake = 0; useNos = false; braking = false;
    // The crash overlay swallows pointer-up events, so a button held during the
    // crash would stay "pressed" forever. Clear all touch state on every start.
    tL = tR = tGas = tBrk = tNos = false;
    dragStartX = null;
    dragSteer = 0;
    cars = [];
    phase = Phase.playing;
  }

  void _tick(Duration e) {
    final dt = ((e - last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    last = e;
    if (phase == Phase.playing) update(dt);
    if (shake > 0) shake -= dt;
    setState(() {});
  }

  void update(double dt) {
    final k = HardwareKeyboard.instance;
    bool key(List<LogicalKeyboardKey> ks) => ks.any(k.isLogicalKeyPressed);
    final left = tL || key([LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA]);
    final right = tR || key([LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD]);
    final gas = tGas || key([LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW]);
    braking = tBrk || key([LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS]);
    final nosKey = tNos || key([LogicalKeyboardKey.space]);

    // Steering: smoothed input, grip grows with speed (can't turn when parked)
    final buttonTarget = (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0);
    final target = dragSteer.abs() > 0.05 ? dragSteer : buttonTarget;
    steer += (target - steer) * min(1.0, 7 * dt);
    final grip = min(1.0, v / 8);
    x += steer * grip * (2.5 + v * 0.09) * dt;

    // Engine, brakes, drag
    useNos = nosKey && nitro > 0 && gas;
    double acc = 7.0; // gentle automatic acceleration from the starting line
    if (gas) {
      acc += 18;
    } else {
      acc -= 3;
    }
    if (useNos) {
      acc += 16;
      nitro = max(0, nitro - 25 * dt);
    } else {
      nitro = min(100, nitro + 6 * dt);
    }
    if (braking) {
      acc -= 30;
    }
    acc -= 0.0085 * v * v;
    v = max(0, v + acc * dt);
    v = min(v, gas ? 58 : 46);

    // Off-road walls: scrape and slow down
    const lim = 1.7;
    if (x.abs() > lim) {
      x = lim * x.sign;
      v = max(0, v - 20 * dt);
      shake = 0.2;
    }
    dist += v * dt;

    // Traffic spawn
    final sc = roadW(size) / 4;
    final zTop = size.height * 0.78 / sc;
    spawnT -= dt;
    if (spawnT <= 0) {
      spawnT = max(0.35, 1.3 - v / 60) + rnd.nextDouble() * 0.5;
      final lx = -1.5 + rnd.nextInt(4);
      final free = !cars.any((c) => c.x == lx && (c.z - (zTop + 3)).abs() < 12);
      if (free) {
        cars.add(Traffic(lx, zTop + 3, 8 + rnd.nextDouble() * 14,
            colors[rnd.nextInt(colors.length)]));
      }
    }

    // Traffic AI: don't drive through the car in front of you in your lane
    for (final a in cars) {
      for (final b in cars) {
        if (a != b && a.x == b.x && b.z > a.z && b.z - a.z < 3 && a.speed > b.speed) {
          a.speed = b.speed;
        }
      }
    }

    for (final c in cars) {
      c.prevZ = c.z;
      c.z += (c.speed - v) * dt;
      if (!c.passed && c.z < -1.2) {
        c.passed = true;
        bonus += (c.x - x).abs() < 1.1 ? 5 : 1; // near-miss bonus
      }
      // Sweep between last frame's and this frame's position so a fast closing
      // speed (or a slow frame) can't skip straight over the player's car.
      final lo = min(c.prevZ, c.z), hi = max(c.prevZ, c.z);
      if ((c.x - x).abs() < 0.55 && lo < 1.05 && hi > -1.05) {
        phase = Phase.over;
        shake = 0.6;
        best = max(best, score);
        break;
      }
    }
    cars.removeWhere((c) => c.z < -12 || c.z > zTop + 30);
  }

  Widget hold(IconData icon, Color col, void Function(bool) f, {double s = 76}) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => f(true),
      onPointerUp: (_) => f(false),
      onPointerCancel: (_) => f(false),
      child: Container(
        width: s, height: s,
        decoration: BoxDecoration(
          color: col.withAlpha(115), shape: BoxShape.circle,
          border: Border.all(color: Colors.white54, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: s * .5),
      ),
    );
  }

  void onDragStart(PointerDownEvent e) {
    if (phase != Phase.playing) return;
    dragStartX = e.position.dx;
  }

  void onDragUpdate(PointerMoveEvent e) {
    if (phase != Phase.playing || dragStartX == null) return;
    final delta = (e.position.dx - dragStartX!) / max(70, size.width * 0.22);
    dragSteer = delta.clamp(-1.0, 1.0);
  }

  void onDragEnd(PointerEvent e) {
    dragStartX = null;
    dragSteer = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, cs) {
        size = Size(cs.maxWidth, cs.maxHeight);
        final shortSide = min(cs.maxWidth, cs.maxHeight);
        final landscape = cs.maxWidth > cs.maxHeight;
        final controlSize = (shortSide * (landscape ? 0.13 : 0.18)).clamp(58.0, 82.0);
        final smallControlSize = (controlSize * 0.84).clamp(52.0, 70.0);
        final horizontalPad = (shortSide * 0.045).clamp(12.0, 24.0);
        final gap = (shortSide * 0.025).clamp(8.0, 16.0);
        final hudSize = landscape ? 18.0 : (shortSide * 0.055).clamp(18.0, 24.0);
        const safeBottom = 8.0;
        final hud = TextStyle(color: Colors.white, fontSize: hudSize, fontWeight: FontWeight.bold);

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: onDragStart,
          onPointerMove: onDragUpdate,
          onPointerUp: onDragEnd,
          onPointerCancel: onDragEnd,
          child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _WorldPainter(this))),
          SafeArea(
            child: Stack(children: [
              Positioned(top: 12, left: horizontalPad, child: Text('Score $score', style: hud)),
              Positioned(top: 8, right: horizontalPad, child: Text('Best $best', style: hud)),
              Positioned(
                top: landscape ? 38 : 46, left: horizontalPad,
                child: SizedBox(
                  width: landscape ? 90 : 110,
                  child: LinearProgressIndicator(
                    value: nitro / 100, minHeight: 8,
                    color: Colors.orangeAccent, backgroundColor: Colors.white24,
                  ),
                ),
              ),
              Positioned(
                bottom: landscape ? 86 : 110, left: 0, right: 0,
                child: Center(child: Text('${(v * 6).round()} km/h', style: hud)),
              ),
              Positioned(
                bottom: safeBottom, left: horizontalPad, right: horizontalPad,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    hold(Icons.arrow_back, Colors.white, (b) => tL = b, s: controlSize),
                    SizedBox(width: gap),
                    hold(Icons.arrow_forward, Colors.white, (b) => tR = b, s: controlSize),
                  ]),
                  Row(children: [
                    hold(Icons.stop, Colors.red, (b) => tBrk = b, s: smallControlSize),
                    SizedBox(width: gap),
                    hold(Icons.bolt, Colors.orange, (b) => tNos = b, s: smallControlSize),
                    SizedBox(width: gap),
                    hold(Icons.keyboard_arrow_up, Colors.green, (b) => tGas = b, s: controlSize),
                  ]),
                ]),
              ),
            ]),
          ),
          if (phase != Phase.playing)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(phase == Phase.menu ? '🚗 NASRR RACER' : '💥 CRASH!',
                      style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(
                    phase == Phase.menu
                        ? 'Weave through traffic. Near misses give bonus points.\n'
                          'Swipe or use arrows to steer • Green = RACE\n'
                          'Start slowly, then build speed • Red = brake • ⚡ = nitro'
                        : 'Score $score   •   Best $best',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: start,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16)),
                    child: Text(phase == Phase.menu ? 'START RACE' : 'PLAY AGAIN',
                        style: const TextStyle(fontSize: 20)),
                  ),
                ]),
              ),
            ),
        ]);
      }),
    );
  }
}

class _WorldPainter extends CustomPainter {
  final _RaceGameState g;
  _WorldPainter(this.g);
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;

  @override
  void paint(Canvas c, Size s) {
    final roadW = g.roadW(s), sc = roadW / 4;
    final cx = s.width / 2, py = s.height * 0.78, left = cx - roadW / 2;
    c.save();
    if (g.shake > 0) {
      c.translate((g.rnd.nextDouble() - .5) * 8, (g.rnd.nextDouble() - .5) * 8);
    }

    // Grass with scrolling stripes
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF2E7D32));
    final sh = sc * 6, goff = (g.dist * sc) % (sh * 2);
    final gp = Paint()..color = const Color(0xFF388E3C);
    for (double y = -sh * 2 + goff; y < s.height; y += sh * 2) {
      c.drawRect(Rect.fromLTWH(0, y, s.width, sh), gp);
    }

    // Trees on the sides
    if (left > 30) {
      final tp = Paint()..color = const Color(0xFF1B5E20);
      for (int i = 0; i < 9; i++) {
        final y = ((i * sc * 4.5 + g.dist * sc) % (s.height + sc * 4)) - sc * 2;
        final r = min(left * 0.3, sc * 0.7);
        c.drawCircle(Offset(left * (i.isEven ? 0.45 : 0.6), y), r, tp);
        c.drawCircle(Offset(s.width - left * (i.isEven ? 0.6 : 0.45), y + sc), r, tp);
      }
    }

    // Road, rumble strips, lane dashes
    c.drawRect(Rect.fromLTWH(left, 0, roadW, s.height), Paint()..color = const Color(0xFF3A3A3A));
    final roff = (g.dist * sc) % (2 * sc);
    for (double y = -2 * sc + roff; y < s.height; y += 2 * sc) {
      final rp = Paint()..color = Colors.redAccent;
      final wp = Paint()..color = Colors.white;
      for (final ex in [left - sc * .14, left + roadW]) {
        c.drawRect(Rect.fromLTWH(ex, y, sc * .14, sc), rp);
        c.drawRect(Rect.fromLTWH(ex, y + sc, sc * .14, sc), wp);
      }
    }
    final doff = (g.dist * sc) % (3.2 * sc);
    final dp = Paint()..color = Colors.white70;
    for (final lx in [-1.0, 0.0, 1.0]) {
      for (double y = -3.2 * sc + doff; y < s.height; y += 3.2 * sc) {
        c.drawRect(Rect.fromLTWH(cx + lx * sc - 3, y, 6, sc * 1.6), dp);
      }
    }

    // Compact start line: kept close behind the player's car.
    final startY = py + sc * 1.55;
    final tile = sc * .28;
    for (int row = 0; row < 2; row++) {
      for (int col = 0; col < 12; col++) {
        final color = (row + col).isEven ? Colors.white : Colors.black;
        c.drawRect(
          Rect.fromLTWH(left + col * roadW / 12, startY + row * tile, roadW / 12, tile),
          Paint()..color = color,
        );
      }
    }

    // Traffic
    for (final t in g.cars) {
      _car(c, Offset(cx + t.x * sc, py - t.z * sc), sc * .62, sc * 1.15, t.color, 0, false, false);
    }

    // Player
    final pos = Offset(cx + g.x * sc, py);
    final ang = g.steer * min(1.0, g.v / 8) * 0.3;
    if (g.useNos) {
      final f = Path()
        ..moveTo(pos.dx - sc * .15, pos.dy + sc * .55)
        ..lineTo(pos.dx, pos.dy + sc * (1.1 + g.rnd.nextDouble() * .4))
        ..lineTo(pos.dx + sc * .15, pos.dy + sc * .55);
      c.drawPath(f, Paint()..color = Colors.orangeAccent);
    }
    _car(c, pos, sc * .62, sc * 1.15, const Color(0xFF00CC44), ang, true, g.braking);

    // Speed lines
    if (g.v > 28) {
      final lp = Paint()
        ..color = Colors.white24
        ..strokeWidth = 2;
      for (int i = 0; i < 14; i++) {
        final lx = ((i * 137) % 100) / 100 * s.width;
        final ly = (((i * 89) % 100) / 100 * s.height + g.dist * sc * 3) % s.height;
        c.drawLine(Offset(lx, ly), Offset(lx, ly + g.v * 1.2), lp);
      }
    }
    c.restore();
  }

  void _car(Canvas c, Offset o, double w, double h, Color col, double a, bool player, bool brake) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(a);
    final p = Paint();
    p.color = Colors.black;
    for (final sx in [-1.0, 1.0]) {
      for (final sy in [-1.0, 1.0]) {
        c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(sx * w * .5, sy * h * .3), width: w * .2, height: h * .22),
              Radius.circular(3)),
          p);
      }
    }
    p.color = col;
    c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(w * .3)),
        p);
    if (player) {
      p.color = Colors.white70;
      c.drawRect(Rect.fromCenter(center: Offset.zero, width: w * .14, height: h * .95), p);
    }
    p.color = const Color(0xFF263238);
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(0, h * .05), width: w * .7, height: h * .36), Radius.circular(5)),
        p);
    p.color = const Color(0xFF87CEEB);
    c.drawRect(Rect.fromCenter(center: Offset(0, -h * .1), width: w * .6, height: h * .14), p);
    p.color = const Color(0xFFFFF59D);
    for (final sx in [-1.0, 1.0]) {
      c.drawCircle(Offset(sx * w * .3, -h * .46), w * .09, p);
    }
    p.color = brake ? Colors.redAccent : const Color(0xFFB71C1C);
    for (final sx in [-1.0, 1.0]) {
      c.drawRect(Rect.fromCenter(center: Offset(sx * w * .3, h * .47), width: w * .2, height: h * .04), p);
    }
    c.restore();
  }
}
