import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/bubble_shooter_logic.dart';

/// Состояние партии — управляет тем, какой оверлей показан.
enum BubbleShooterPhase { ready, running, dead }

/// Цвет пузыря в палитре проекта.
Color bubbleColor(Bubble b) {
  switch (b) {
    case Bubble.red:
      return const Color(0xFFFF5370);
    case Bubble.yellow:
      return const Color(0xFFFFD54F);
    case Bubble.green:
      return const Color(0xFF5CE08A);
    case Bubble.blue:
      return const Color(0xFF4ECDC4);
    case Bubble.purple:
      return const Color(0xFF7C5CFF);
  }
}

/// Flame-игра «Bubble Shooter»: соты пузырей сверху, пушка снизу. Drag задаёт
/// угол (ограничен вверх), отпускание/тап стреляет — пузырь летит с отскоком от
/// стен, прилипает к сотам, лопает кластер ≥3 и роняет «висящие».
///
/// Чистая механика — в [BubbleShooterLogic]; здесь анимация полёта, ввод, рендер
/// и «сок»: частицы в цвет при лопании, падение, тряска и вспышка.
class BubbleShooterFlameGame extends FlameGame {
  BubbleShooterFlameGame({required this.onGameOver});

  /// Вызывается при конце партии со счётом (для рекордов/оверлея).
  final void Function(int score) onGameOver;

  final BubbleShooterLogic _logic = BubbleShooterLogic();
  final Random _rng = Random();

  // Наблюдаемое для оверлеев/HUD.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> combo = ValueNotifier(0);
  final ValueNotifier<int> bubbles = ValueNotifier(0);
  final ValueNotifier<int> level = ValueNotifier(1);
  final ValueNotifier<double> fps = ValueNotifier(0);
  final ValueNotifier<BubbleShooterPhase> phase =
      ValueNotifier(BubbleShooterPhase.ready);

  // ВАЖНО: своё имя, т.к. у FlameGame уже есть member `paused`.
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  bool get _running => phase.value == BubbleShooterPhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  // Прицел: угол от вертикали (0 — вверх). Ограничен, чтобы не стрелять вбок/вниз.
  double _aimAngle = 0;
  static const double _maxAim = 1.30; // ~75° от вертикали в каждую сторону

  // Кнопочное вращение прицела: -1..1 (0 — стоп). Применяется в [update].
  double _aimDir = 0;
  static const double _kAimSpeed = 1.1; // рад/сек (мягче для точной наводки)

  /// Кнопочный прицел: [dir] -1..1 (0 — стоп). Влево/вправо крутит угол.
  void setAimDir(double dir) {
    _aimDir = dir.clamp(-1.0, 1.0);
    // Тап тоже поворачивает прицел — сразу небольшой шаг.
    if (_aimDir != 0 && _shot == null && _active) {
      _aimAngle = (_aimAngle + _aimDir * 0.045).clamp(-_maxAim, _maxAim);
    }
  }

  // Летящий снаряд (анимация выстрела). Когда не null — ввод выстрела заблокирован.
  _Projectile? _shot;
  // Цвет летящего снаряда и его цель: поле меняем только в момент «приземления»,
  // чтобы лопание не происходило раньше визуального касания.
  Bubble? _shotColor;
  HexCell? _shotTarget;
  static const double _shotSpeed = 26; // диаметров в секунду

  // Эффекты.
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  final List<_Faller> _fallers = [];
  double _shake = 0;
  double _flash = 0;
  Color _flashColor = Colors.white;

  // Сглаженный FPS для отладочного индикатора.
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // Геометрия поля (считается в render по текущему размеру).
  static const double _topInset = 150; // место под HUD (счёт/рекорд/пауза)
  static const double _bottomInset = 96; // место под пушку
  double _scale = 0; // пикселей на «диаметр пузыря»
  Offset _origin = Offset.zero;

  void start() {
    _logic.reset();
    score.value = 0;
    combo.value = 0;
    bubbles.value = _logic.bubbleCount;
    level.value = _logic.level;
    _aimAngle = 0;
    _aimDir = 0;
    _shot = null;
    _shotColor = null;
    _shotTarget = null;
    _sparks.clear();
    _popups.clear();
    _fallers.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = BubbleShooterPhase.running;
  }

  // ── Ввод ────────────────────────────────────────────────────────────────────

  /// Навести пушку в точку касания [local] (в пикселях экрана).
  void aimAt(Offset local) {
    if (!_active || _shot != null) return;
    if (_scale <= 0) return;
    final muzzle = _muzzlePx();
    final dx = local.dx - muzzle.dx;
    final dy = local.dy - muzzle.dy;
    // Угол от вертикали вверх. Точку ниже пушки трактуем как почти горизонталь.
    if (dy >= 0) {
      _aimAngle = dx >= 0 ? _maxAim : -_maxAim;
      return;
    }
    final a = atan2(dx, -dy);
    _aimAngle = a.clamp(-_maxAim, _maxAim);
  }

  /// Выстрелить под текущим углом (отпускание пальца или тап).
  ///
  /// Цель вычисляем сразу ([BubbleShooterLogic.trace] — без мутаций поля), но
  /// сам пузырь прилепляем/лопаем только когда снаряд долетит (см. [_advanceShot]).
  /// Так лопание не «обгоняет» полёт. Пушку тоже прокручиваем по прилёту, поэтому
  /// во время полёта дуло показывает уже летящий цвет — это и нужно.
  void shoot() {
    if (!_active || _shot != null) return;
    final shotColor = _logic.current;
    final target = _logic.trace(_aimAngle); // только чтение, поле не меняется
    _shotColor = shotColor;
    _shotTarget = target;

    // Снаряд летит по той же траектории (с отскоком) до цели (или до верха/стены,
    // если прилепить некуда — тогда по прилёту просто «отказ»).
    final path = _buildPath(_aimAngle, target);
    _shot = _Projectile(color: shotColor, path: path);
    Haptics.light();
  }

  // ── Цикл ──────────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    super.update(dt);

    _fpsFrames++;
    _fpsAcc += dt;
    if (_fpsAcc >= 0.5) {
      fps.value = _fpsFrames / _fpsAcc;
      _fpsFrames = 0;
      _fpsAcc = 0;
    }

    _advanceEffects(dt);

    if (!_active) return;

    if (_aimDir != 0 && _shot == null) {
      _aimAngle =
          (_aimAngle + _aimDir * _kAimSpeed * dt).clamp(-_maxAim, _maxAim);
    }
    _advanceShot(dt);
  }

  /// Продвинуть летящий снаряд по ломаной; по прилёте применить ход к полю.
  void _advanceShot(double dt) {
    final shot = _shot;
    if (shot == null) return;

    shot.t += dt * _shotSpeed;
    if (shot.t < shot.length) return;

    // Долетел — теперь меняем поле и прокручиваем пушку.
    _shot = null;
    final color = _shotColor;
    final target = _shotTarget;
    _shotColor = null;
    _shotTarget = null;

    if (color == null || target == null) {
      // Прилепить некуда — лёгкий «отказ», но цвет в пушке всё равно сменим,
      // чтобы игрок не застрял.
      _shake = max(_shake, 0.12);
      _logic.cycleCannon();
      return;
    }

    final result = _logic.placeAndResolve(target, color);
    _logic.cycleCannon();
    _applyResult(result);
  }

  void _applyResult(ShotResult result) {
    score.value = _logic.score;
    bubbles.value = _logic.bubbleCount;

    if (result.cleared.isEmpty) {
      // Просто прилип — без лопания. Комбо сбрасываем.
      combo.value = 0;
      Haptics.select();
    } else {
      // Лопнул кластер: частицы в цвет на каждом лопнутом пузыре.
      for (final p in result.cleared) {
        final c = _logic.centerOf(p.cell);
        _spawnBurst(c.x, c.y, bubbleColor(p.bubble), count: 8);
      }
      // Упавшие пузыри — анимация падения + частицы.
      for (final d in result.dropped) {
        final c = _logic.centerOf(d.cell);
        _fallers.add(_Faller(
          gridX: c.x,
          gridY: c.y,
          color: bubbleColor(d.bubble),
          vy: 4 + _rng.nextDouble() * 3,
        ));
      }

      combo.value = result.removed;
      final landCenter = _logic.centerOf(result.landed!);
      _popups.add(_Popup(
        gridX: landCenter.x,
        gridY: landCenter.y,
        text: '+${result.gained}',
        color: Colors.white,
        big: result.dropped.isNotEmpty || result.removed >= 6,
      ));

      _shake = max(_shake, 0.25 + result.removed * 0.02);
      if (result.dropped.isNotEmpty) {
        _flash = max(_flash, 0.22);
        _flashColor = const Color(0xFF5CE08A);
        _popups.add(_Popup(
          gridX: _logic.fieldWidth / 2,
          gridY: 2,
          text: '${result.dropped.length} DROP!',
          color: const Color(0xFFFFD54F),
          big: true,
        ));
        Haptics.combo((result.removed ~/ 3).clamp(2, 5));
      } else {
        Haptics.medium();
      }
    }

    if (result.boardCleared) {
      level.value = result.level;
      _flash = max(_flash, 0.6);
      _flashColor = const Color(0xFF5CE08A);
      _shake = max(_shake, 0.5);
      _popups.add(_Popup(
        gridX: _logic.fieldWidth / 2,
        gridY: 3,
        text: 'УРОВЕНЬ ${result.level}!',
        color: const Color(0xFFFFD54F),
        big: true,
      ));
      Haptics.combo(5);
    }

    if (result.gameOver) _onGameOver();
  }

  void _onGameOver() {
    _shake = 1;
    _flash = 1;
    _flashColor = const Color(0xFFFF5370);
    Haptics.heavy();
    // Сначала отдать счёт (экран посчитает рекорд), затем сменить фазу.
    onGameOver(score.value);
    phase.value = BubbleShooterPhase.dead;
  }

  // ── Эффекты ────────────────────────────────────────────────────────────────

  void _spawnBurst(double gx, double gy, Color color, {int count = 8}) {
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 3 + _rng.nextDouble() * 7; // в диаметрах/сек
      _sparks.add(_Spark(
        gridX: gx,
        gridY: gy,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.35 + _rng.nextDouble() * 0.4,
        color: color,
      ));
    }
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.4);
    _flash = max(0, _flash - dt * 1.8);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = s.vel * (1 - 2.4 * dt);
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);

    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.duration);

    for (final f in _fallers) {
      f.vy += dt * 24; // гравитация в диаметрах/сек^2
      f.gridY += f.vy * dt;
    }
    // Падать за нижнюю границу поля и исчезать.
    final maxY = _logic.rows * BubbleShooterLogic.rowHeight + 3;
    _fallers.removeWhere((f) => f.gridY > maxY);
  }

  // ── Геометрия ──────────────────────────────────────────────────────────────

  void _computeGeometry() {
    final fieldW = _logic.fieldWidth;
    final fieldH = _logic.rows * BubbleShooterLogic.rowHeight + 2 * BubbleShooterLogic.radius;
    final c = buildContext;
    final safeTop = c == null ? 0.0 : (MediaQuery.maybeOf(c)?.padding.top ?? 0.0);
    final top = _topInset + safeTop;
    final availH = size.y - top - _bottomInset;
    _scale = min(size.x / fieldW, availH / fieldH);
    final w = _scale * fieldW;
    _origin = Offset((size.x - w) / 2, top);
  }

  Offset _toPx(double gx, double gy) =>
      _origin + Offset(gx * _scale, gy * _scale);

  /// Пиксельная позиция дула пушки (центр вылета у нижней кромки поля).
  Offset _muzzlePx() => _toPx(
        _logic.fieldWidth / 2,
        _logic.rows * BubbleShooterLogic.rowHeight + BubbleShooterLogic.radius,
      );

  // ── Рендер ───────────────────────────────────────────────────────────────────

  @override
  Color backgroundColor() => const Color(0xFF0E0B1A);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _computeGeometry();

    if (_shake > 0) {
      final m = _shake * _shake * 9;
      canvas.save();
      canvas.translate(
        (_rng.nextDouble() * 2 - 1) * m,
        (_rng.nextDouble() * 2 - 1) * m,
      );
    }

    _drawField(canvas);
    _drawBubbles(canvas);
    _drawFallers(canvas);
    if (_active) _drawAim(canvas);
    _drawShot(canvas);
    _drawCannon(canvas);
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = _flashColor.withValues(alpha: _flash * 0.4),
      );
    }
  }

  void _drawField(Canvas canvas) {
    final fieldW = _logic.fieldWidth * _scale;
    final fieldH =
        (_logic.rows * BubbleShooterLogic.rowHeight + 2 * BubbleShooterLogic.radius) *
            _scale;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (_origin & Size(fieldW, fieldH)).inflate(_scale * 0.12),
        Radius.circular(_scale * 0.4),
      ),
      Paint()..color = const Color(0xFF161126),
    );

    // Линия проигрыша — верх последнего ряда.
    final lineY = _toPx(0, (_logic.rows - 1) * BubbleShooterLogic.rowHeight).dy;
    final paint = Paint()
      ..color = const Color(0xFFFF5370).withValues(alpha: 0.35)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(_origin.dx, lineY),
      Offset(_origin.dx + fieldW, lineY),
      paint,
    );
  }

  void _drawBubbles(Canvas canvas) {
    for (var row = 0; row < _logic.rows; row++) {
      for (var col = 0; col < _logic.colsInRow(row); col++) {
        final b = _logic.bubbleAt(row, col);
        if (b == null) continue;
        final c = _logic.centerOf(HexCell(row, col));
        _drawBubbleAt(canvas, _toPx(c.x, c.y), bubbleColor(b), _scale * 0.46);
      }
    }
  }

  void _drawBubbleAt(Canvas canvas, Offset center, Color color, double r) {
    canvas.drawCircle(center, r, Paint()..color = color);
    // Блик сверху-слева для объёма.
    canvas.drawCircle(
      center - Offset(r * 0.32, r * 0.32),
      r * 0.34,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    // Тонкая тёмная окантовка.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.08
        ..color = Colors.black.withValues(alpha: 0.18),
    );
  }

  void _drawFallers(Canvas canvas) {
    for (final f in _fallers) {
      final alpha = (1 - f.gridY /
              (_logic.rows * BubbleShooterLogic.rowHeight + 3))
          .clamp(0.0, 1.0);
      canvas.drawCircle(
        _toPx(f.gridX, f.gridY),
        _scale * 0.46,
        Paint()..color = f.color.withValues(alpha: 0.4 + 0.6 * alpha),
      );
    }
  }

  /// Пунктирный луч прицела от дула под текущим углом (короткий — только намёк).
  void _drawAim(Canvas canvas) {
    if (_shot != null) return;
    final muzzle = _muzzlePx();
    final dir = Offset(sin(_aimAngle), -cos(_aimAngle));
    final paint = Paint()
      ..color = bubbleColor(_logic.current).withValues(alpha: 0.5)
      ..strokeWidth = _scale * 0.12
      ..strokeCap = StrokeCap.round;
    const dashes = 9;
    final segLen = _scale * 1.4;
    for (var i = 0; i < dashes; i++) {
      final a = muzzle + dir * (segLen * (i * 1.6));
      final b = a + dir * (segLen * 0.7);
      final fade = 1 - i / dashes;
      canvas.drawLine(
        a,
        b,
        paint..color = bubbleColor(_logic.current).withValues(alpha: 0.5 * fade),
      );
    }
  }

  void _drawShot(Canvas canvas) {
    final shot = _shot;
    if (shot == null) return;
    final p = shot.positionAt(shot.t);
    _drawBubbleAt(canvas, _toPx(p.dx, p.dy), bubbleColor(shot.color), _scale * 0.46);
  }

  void _drawCannon(Canvas canvas) {
    final muzzle = _muzzlePx();
    // Основание пушки.
    canvas.drawCircle(
      muzzle,
      _scale * 0.75,
      Paint()..color = const Color(0xFF2A2147),
    );
    // Ствол по направлению прицела.
    final dir = Offset(sin(_aimAngle), -cos(_aimAngle));
    final barrelEnd = muzzle + dir * (_scale * 1.0);
    canvas.drawLine(
      muzzle,
      barrelEnd,
      Paint()
        ..color = const Color(0xFF4A3C7A)
        ..strokeWidth = _scale * 0.5
        ..strokeCap = StrokeCap.round,
    );
    // Текущий заряд.
    _drawBubbleAt(canvas, muzzle, bubbleColor(_logic.current), _scale * 0.5);
    // «Следующий» цвет — маленький слева от пушки.
    final nextCenter = muzzle + Offset(-_scale * 1.7, 0);
    _drawBubbleAt(canvas, nextCenter, bubbleColor(_logic.next), _scale * 0.3);
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      canvas.drawCircle(
        _toPx(s.gridX, s.gridY) + s.pos * _scale,
        _scale * 0.16 * k,
        Paint()..color = s.color.withValues(alpha: k),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = (p.big ? 1.0 : 0.7) * (1 + 0.3 * (1 - k));
      final center = _toPx(p.gridX, p.gridY) - Offset(0, k * _scale * 1.6);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: alpha),
            fontSize: _scale * scale,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  // ── Построение траектории снаряда ────────────────────────────────────────────

  /// Построить ломаную полёта (в координатах поля) от дула под углом [angleRad]
  /// до центра целевой ячейки [target] (с учётом отскоков от стен). Если цели
  /// нет — короткий путь до верха/стены.
  _Path _buildPath(double angleRad, HexCell? target) {
    final points = <Offset>[];
    final startX = _logic.fieldWidth / 2;
    final startY = _logic.rows * BubbleShooterLogic.rowHeight + BubbleShooterLogic.radius;
    points.add(Offset(startX, startY));

    final minX = BubbleShooterLogic.radius;
    final maxX = _logic.fieldWidth - BubbleShooterLogic.radius;
    var vx = sin(angleRad);
    var vy = -cos(angleRad);
    final len = sqrt(vx * vx + vy * vy);
    if (len != 0) {
      vx /= len;
      vy /= len;
    }

    final targetCenter =
        target != null ? _logic.centerOf(target) : null;
    var px = startX;
    var py = startY;
    const step = 0.1;
    const maxSteps = 5000;
    for (var i = 0; i < maxSteps; i++) {
      var nx = px + vx * step;
      var ny = py + vy * step;
      if (nx < minX) {
        nx = minX + (minX - nx);
        vx = -vx;
        points.add(Offset(px, py)); // узел отскока
      } else if (nx > maxX) {
        nx = maxX - (nx - maxX);
        vx = -vx;
        points.add(Offset(px, py));
      }
      px = nx;
      py = ny;

      if (targetCenter != null) {
        // Дошли до уровня целевого ряда (пузырь летит вверх, py убывает) —
        // финальным узлом подставим центр цели. Гарантирует короткий путь и
        // снимает «зависание»: прямой путь мог не попасть в окрестность
        // смещённой ячейки и тянуть до maxSteps (полёт на десятки секунд).
        if (py <= targetCenter.y) break;
      } else if (py <= BubbleShooterLogic.radius) {
        break;
      }
    }
    points.add(targetCenter != null
        ? Offset(targetCenter.x, targetCenter.y)
        : Offset(px, py));
    return _Path(points);
  }
}

/// Ломаная-траектория снаряда с равномерным движением по длине.
class _Path {
  _Path(this.points) {
    var acc = 0.0;
    _cum.add(0);
    for (var i = 1; i < points.length; i++) {
      acc += (points[i] - points[i - 1]).distance;
      _cum.add(acc);
    }
    length = acc;
  }

  final List<Offset> points;
  final List<double> _cum = [];
  late final double length;

  /// Точка на расстоянии [d] от начала вдоль ломаной.
  Offset at(double d) {
    if (points.length == 1) return points.first;
    if (d <= 0) return points.first;
    if (d >= length) return points.last;
    // Линейный поиск сегмента (точек мало — пара-тройка).
    var seg = 1;
    while (seg < _cum.length && _cum[seg] < d) {
      seg++;
    }
    final segStart = _cum[seg - 1];
    final segLen = _cum[seg] - segStart;
    final t = segLen == 0 ? 0.0 : (d - segStart) / segLen;
    return Offset.lerp(points[seg - 1], points[seg], t)!;
  }
}

/// Летящий снаряд: цвет и его путь; [t] — пройденная длина.
class _Projectile {
  _Projectile({required this.color, required _Path path}) : _path = path;

  final Bubble color;
  final _Path _path;
  double t = 0;

  double get length => _path.length;
  Offset positionAt(double d) => _path.at(d);
}

class _Spark {
  _Spark({
    required this.gridX,
    required this.gridY,
    required this.vel,
    required this.life,
    required this.color,
  });
  final double gridX;
  final double gridY;
  Offset pos = Offset.zero; // смещение в диаметрах от точки рождения
  Offset vel;
  final double life;
  final Color color;
  double age = 0;
}

class _Popup {
  _Popup({
    required this.gridX,
    required this.gridY,
    required this.text,
    required this.color,
    this.big = false,
  });
  static const double duration = 1.0;
  final double gridX;
  final double gridY;
  final String text;
  final Color color;
  final bool big;
  double age = 0;
}

class _Faller {
  _Faller({
    required this.gridX,
    required this.gridY,
    required this.color,
    required this.vy,
  });
  final double gridX;
  double gridY;
  final Color color;
  double vy;
}
