import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/block_puzzle_logic.dart';

/// Фаза партии — управляет показываемым оверлеем.
enum BlockPuzzlePhase { ready, running, dead }

/// Цвет «кирпича» в палитре проекта.
Color blockColor(BlockColor c) {
  switch (c) {
    case BlockColor.teal:
      return const Color(0xFF4ECDC4);
    case BlockColor.yellow:
      return const Color(0xFFFFD54F);
    case BlockColor.violet:
      return const Color(0xFF7C5CFF);
    case BlockColor.green:
      return const Color(0xFF5CE08A);
    case BlockColor.pink:
      return const Color(0xFFFF6FAE);
    case BlockColor.blue:
      return const Color(0xFF5C8CFF);
    case BlockColor.orange:
      return const Color(0xFFFF9F45);
  }
}

/// Flame-игра «1010!»: перетаскивай фигуры из лотка на поле 10×10, заполняй
/// строки и столбцы — они сгорают со вспышкой и частицами. Бесконечный режим
/// ради рекорда; «сок» (частицы/попапы/шейк/вспышка) живёт здесь.
///
/// Имя класса — [BlockPuzzleFlameGame] (идентификатор Dart не может начинаться
/// с цифры, поэтому не «1010FlameGame»); «1010!» — отображаемое название.
class BlockPuzzleFlameGame extends FlameGame {
  BlockPuzzleFlameGame({required this.onGameOver});

  final void Function(int score) onGameOver;

  final BlockPuzzleLogic _logic = BlockPuzzleLogic();
  final Random _rng = Random();

  // Наблюдаемое для HUD/оверлеев. Лоток и поле рисуются прямо на canvas (Flame
  // перерисовывает каждый кадр), поэтому отдельного нотифаера им не нужно.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> combo = ValueNotifier(0);
  final ValueNotifier<BlockPuzzlePhase> phase =
      ValueNotifier(BlockPuzzlePhase.ready);
  final ValueNotifier<double> fps = ValueNotifier(0);
  // ВАЖНО: именно isPaused — у FlameGame уже есть свой член `paused`.
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  // ── Геометрия ──────────────────────────────────────────────────────────────
  static const double _topInset = 132; // место под HUD сверху
  static const double _bottomInset = 24;
  static const double _trayGap = 18; // зазор между полем и лотком
  double _cell = 0; // размер клетки поля
  Offset _origin = Offset.zero; // левый верхний угол поля
  // Лоток: три слота в ряд под полем.
  double _trayTop = 0;
  double _traySlotW = 0;
  double _trayCell = 0; // размер клетки фигур в лотке

  // ── Перетаскивание ─────────────────────────────────────────────────────────
  int _dragIndex = -1; // индекс схваченной фигуры лотка (или -1)
  Offset _dragPos = Offset.zero; // текущая позиция пальца (в пикселях)
  // Смещение «пальца» от якорной (0,0) клетки фигуры в пикселях — чтобы фигура
  // ощущалась поднятой над пальцем, а не под ним.
  Offset _grabOffset = Offset.zero;

  // ── Эффекты ─────────────────────────────────────────────────────────────────
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  final List<_CellFlash> _flashes = [];
  double _shake = 0;
  double _flash = 0;
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  bool get _running => phase.value == BlockPuzzlePhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  // ── Управление состоянием ────────────────────────────────────────────────
  void start() {
    _logic.reset();
    score.value = 0;
    combo.value = 0;
    _dragIndex = -1;
    _sparks.clear();
    _popups.clear();
    _flashes.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = BlockPuzzlePhase.running;
  }

  // ── Ввод (вызывается экраном) ────────────────────────────────────────────

  /// Палец опустился в точке [local]. Если это слот лотка с фигурой — берём её.
  void onDragStart(Offset local) {
    if (!_active) return;
    final idx = _trayIndexAt(local);
    if (idx < 0) return;
    final piece = _logic.tray[idx];
    if (piece == null) return;
    _dragIndex = idx;
    // Поднимаем фигуру так, чтобы палец держал её центр по X и был чуть ниже.
    _grabOffset = Offset(
      piece.shape.width * _cell / 2,
      piece.shape.height * _cell + _cell * 0.4,
    );
    _dragPos = local;
    Haptics.select();
  }

  /// Палец двигается. Просто запоминаем позицию (превью рисуется в render).
  void onDragUpdate(Offset local) {
    if (_dragIndex < 0) return;
    _dragPos = local;
  }

  /// Палец отпущен. Пробуем поставить схваченную фигуру в наведённую клетку.
  void onDragEnd() {
    if (_dragIndex < 0) return;
    final idx = _dragIndex;
    _dragIndex = -1;
    if (!_active) return;

    final anchor = _hoverAnchor(idx);
    if (anchor == null) {
      _shake = max(_shake, 0.18);
      Haptics.light();
      return;
    }
    final res = _logic.place(idx, anchor.x, anchor.y);
    if (!res.placed) {
      _shake = max(_shake, 0.18);
      Haptics.light();
      return;
    }
    _onPlaced(res);
  }

  /// Палец/жест отменён (например, увели за край) — роняем фигуру обратно.
  void onDragCancel() {
    _dragIndex = -1;
  }

  void _onPlaced(PlaceResult res) {
    score.value = _logic.score;

    // Всплеск при установке — короткая пыль по клеткам фигуры.
    for (final c in res.placedCells) {
      _spawnPuff(c.x + 0.5, c.y + 0.5, Colors.white, count: 2);
    }

    if (res.linesCleared > 0) {
      combo.value = res.linesCleared;
      _onLinesCleared(res);
    } else {
      combo.value = 0;
      Haptics.medium();
    }

    if (res.gameOver) {
      phase.value = BlockPuzzlePhase.dead;
      _shake = 1;
      _flash = max(_flash, 0.6);
      Haptics.heavy();
      onGameOver(score.value);
    }
  }

  void _onLinesCleared(PlaceResult res) {
    for (final c in res.clearedCells) {
      _flashes.add(_CellFlash(x: c.pos.x, y: c.pos.y));
      _spawnBurst(c.pos.x + 0.5, c.pos.y + 0.5, blockColor(c.color));
    }

    final lines = res.linesCleared;
    _shake = max(_shake, 0.35 + lines * 0.18);
    _flash = max(_flash, lines >= 3 ? 0.5 : 0.22);

    final String label;
    final Color color;
    if (lines >= 3) {
      label = '$lines В РЯД!';
      color = const Color(0xFFFFD54F);
    } else if (lines == 2) {
      label = 'ДВОЙНАЯ!';
      color = const Color(0xFFFF6FAE);
    } else {
      label = '+${res.gained}';
      color = Colors.white;
    }
    _popups.add(_Popup(
      gridX: BlockPuzzleLogic.size / 2,
      gridY: BlockPuzzleLogic.size / 2,
      text: label,
      color: color,
      big: lines >= 2,
    ));

    if (lines >= 2) {
      Haptics.combo(lines.clamp(2, 5));
    } else {
      Haptics.medium();
    }
  }

  // ── Геометрия: хелперы ──────────────────────────────────────────────────────

  // Клетка фигуры в лотке мельче клетки поля; высота слота вмещает самую
  // высокую фигуру (вертикальная палочка из 5 клеток) с небольшим запасом.
  static const double _trayCellK = 0.5; // доля от клетки поля
  static const double _traySlotCells = 6; // высота слота в клетках лотка

  void _computeGeometry() {
    // Поле квадратное, ширина ограничивает размер клетки; снизу оставляем полосу
    // под ряд лотка высотой [_traySlotCells] клеток лотка плюс зазор.
    final maxBoard = size.x - 16;
    final approxCell = maxBoard / BlockPuzzleLogic.size;
    final trayBand = _trayGap + _traySlotCells * _trayCellK * approxCell;
    final availH = size.y - _topInset - _bottomInset - trayBand;
    _cell = min(approxCell, availH / BlockPuzzleLogic.size);
    final boardSize = _cell * BlockPuzzleLogic.size;
    _origin = Offset((size.x - boardSize) / 2, _topInset);

    _trayTop = _origin.dy + boardSize + _trayGap;
    _traySlotW = boardSize / BlockPuzzleLogic.traySize;
    _trayCell = _cell * _trayCellK;
  }

  Rect _slotRect(int i) => Rect.fromLTWH(
        _origin.dx + i * _traySlotW,
        _trayTop,
        _traySlotW,
        _trayCell * _traySlotCells,
      );

  /// Над каким слотом лотка точка [local] (или -1).
  int _trayIndexAt(Offset local) {
    for (var i = 0; i < BlockPuzzleLogic.traySize; i++) {
      if (_slotRect(i).contains(local)) return i;
    }
    return -1;
  }

  /// Габариты фигуры в пикселях при размере клетки лотка.
  Size _trayPieceSize(BlockShape s) =>
      Size(s.width * _trayCell, s.height * _trayCell);

  /// Левый верхний угол фигуры внутри её слота (центрируем по слоту).
  Offset _trayPieceOrigin(int i, BlockShape s) {
    final slot = _slotRect(i);
    final ps = _trayPieceSize(s);
    return Offset(
      slot.left + (slot.width - ps.width) / 2,
      slot.top + (slot.height - ps.height) / 2,
    );
  }

  /// Какая якорная клетка поля под перетаскиваемой фигурой [idx], если ход
  /// валиден — иначе null. Якорь = локальная (0,0) клетки фигуры.
  Point<int>? _hoverAnchor(int idx) {
    final piece = _logic.tray[idx];
    if (piece == null || _cell <= 0) return null;
    final topLeft = _dragPos - _grabOffset;
    final ax = ((topLeft.dx - _origin.dx) / _cell).round();
    final ay = ((topLeft.dy - _origin.dy) / _cell).round();
    if (!_logic.canPlaceShape(piece.shape, ax, ay)) return null;
    return Point(ax, ay);
  }

  // ── Эффекты ─────────────────────────────────────────────────────────────────

  void _spawnBurst(double gx, double gy, Color color) {
    for (var i = 0; i < 6; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 60 + _rng.nextDouble() * 150;
      _sparks.add(_Spark(
        gridX: gx,
        gridY: gy,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.35 + _rng.nextDouble() * 0.4,
        color: color,
      ));
    }
  }

  void _spawnPuff(double gx, double gy, Color color, {int count = 3}) {
    for (var i = 0; i < count; i++) {
      _sparks.add(_Spark(
        gridX: gx,
        gridY: gy,
        vel: Offset(
          (_rng.nextDouble() * 2 - 1) * 70,
          -_rng.nextDouble() * 70,
        ),
        life: 0.2 + _rng.nextDouble() * 0.25,
        color: color,
      ));
    }
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.4);
    _flash = max(0, _flash - dt * 1.8);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.4 * dt), s.vel.dy + 200 * dt);
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);

    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.duration);

    for (final f in _flashes) {
      f.age += dt;
    }
    _flashes.removeWhere((f) => f.age >= _CellFlash.duration);
  }

  // ── Игровой цикл ──────────────────────────────────────────────────────────

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
    // «1010!» — ход дискретный (по отпусканию пальца), непрерывной прогрессии
    // во времени нет; вся логика хода живёт в onDragEnd.
  }

  // ── Рендер ───────────────────────────────────────────────────────────────

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

    _drawBoard(canvas);
    _drawStack(canvas);
    if (_running) {
      _drawHover(canvas);
      _drawTray(canvas);
      _drawDragged(canvas);
    }
    _drawFlashes(canvas);
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = Colors.white.withValues(alpha: _flash * 0.35),
      );
    }
  }

  Rect _cellRect(num gx, num gy) => Rect.fromLTWH(
        _origin.dx + gx * _cell,
        _origin.dy + gy * _cell,
        _cell,
        _cell,
      );

  Offset _point(double gx, double gy) =>
      _origin + Offset(gx * _cell, gy * _cell);

  void _drawBoard(Canvas canvas) {
    final boardSize = _cell * BlockPuzzleLogic.size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (_origin & Size(boardSize, boardSize)).inflate(_cell * 0.14),
        Radius.circular(_cell * 0.3),
      ),
      Paint()..color = const Color(0xFF161126),
    );
    // Пустые ячейки — деликатные «лунки» для читаемости поля.
    final hole = Paint()..color = const Color(0xFF1E1736);
    for (var y = 0; y < BlockPuzzleLogic.size; y++) {
      for (var x = 0; x < BlockPuzzleLogic.size; x++) {
        if (_logic.board[y][x] != null) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            _cellRect(x, y).deflate(_cell * 0.08),
            Radius.circular(_cell * 0.2),
          ),
          hole,
        );
      }
    }
  }

  void _drawBlock(Canvas canvas, Rect rect, Color color,
      {double alpha = 1, double radiusK = 0.22, bool glow = false}) {
    final r = rect.deflate(rect.width * 0.06);
    final rrect = RRect.fromRectAndRadius(r, Radius.circular(rect.width * radiusK));
    if (glow) {
      canvas.drawRRect(
        rrect.inflate(2),
        Paint()
          ..color = color.withValues(alpha: 0.5 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: alpha));
    // Блик сверху для объёма.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.32),
        Radius.circular(rect.width * radiusK),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.18 * alpha),
    );
  }

  void _drawStack(Canvas canvas) {
    for (var y = 0; y < BlockPuzzleLogic.size; y++) {
      for (var x = 0; x < BlockPuzzleLogic.size; x++) {
        final c = _logic.board[y][x];
        if (c != null) _drawBlock(canvas, _cellRect(x, y), blockColor(c));
      }
    }
  }

  /// Подсветка клеток под перетаскиваемой фигурой: зелёная при валидном ходе,
  /// красная при недопустимом (фигура «приклеена» к решётке поля).
  void _drawHover(Canvas canvas) {
    if (_dragIndex < 0) return;
    final piece = _logic.tray[_dragIndex];
    if (piece == null) return;
    // При недопустимом ходе подсветки нет — «летящая» фигура рисуется отдельно.
    final anchor = _hoverAnchor(_dragIndex);
    if (anchor == null) return;
    final color = blockColor(piece.color);
    for (final c in piece.shape.cells) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _cellRect(anchor.x + c.x, anchor.y + c.y).deflate(_cell * 0.06),
          Radius.circular(_cell * 0.22),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.6),
      );
    }
  }

  void _drawTray(Canvas canvas) {
    for (var i = 0; i < BlockPuzzleLogic.traySize; i++) {
      if (i == _dragIndex) continue; // схваченная рисуется отдельно
      final piece = _logic.tray[i];
      if (piece == null) continue;
      final origin = _trayPieceOrigin(i, piece.shape);
      final color = blockColor(piece.color);
      for (final c in piece.shape.cells) {
        final rect = Rect.fromLTWH(
          origin.dx + c.x * _trayCell,
          origin.dy + c.y * _trayCell,
          _trayCell,
          _trayCell,
        );
        _drawBlock(canvas, rect, color);
      }
    }
  }

  /// Перетаскиваемая фигура: в размере клетки ПОЛЯ, привязанная к решётке когда
  /// ход валиден (магнит), иначе свободно следует за пальцем.
  void _drawDragged(Canvas canvas) {
    if (_dragIndex < 0) return;
    final piece = _logic.tray[_dragIndex];
    if (piece == null) return;
    final anchor = _hoverAnchor(_dragIndex);
    final color = blockColor(piece.color);

    if (anchor != null) {
      // Магнит к решётке — рисуем прямо в целевых клетках, ярко.
      for (final c in piece.shape.cells) {
        _drawBlock(canvas, _cellRect(anchor.x + c.x, anchor.y + c.y), color,
            glow: true);
      }
      return;
    }

    // Свободно «парит» под пальцем, чуть прозрачнее.
    final topLeft = _dragPos - _grabOffset;
    for (final c in piece.shape.cells) {
      final rect = Rect.fromLTWH(
        topLeft.dx + c.x * _cell,
        topLeft.dy + c.y * _cell,
        _cell,
        _cell,
      );
      _drawBlock(canvas, rect, color, alpha: 0.85, glow: true);
    }
  }

  void _drawFlashes(Canvas canvas) {
    for (final f in _flashes) {
      final k = 1 - f.age / _CellFlash.duration;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _cellRect(f.x, f.y).deflate(_cell * 0.04),
          Radius.circular(_cell * 0.2),
        ),
        Paint()..color = Colors.white.withValues(alpha: k * 0.85),
      );
    }
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      canvas.drawCircle(
        _point(s.gridX, s.gridY) + s.pos,
        _cell * 0.14 * k,
        Paint()..color = s.color.withValues(alpha: k),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = (p.big ? 1.0 : 0.7) * (1 + 0.3 * (1 - k));
      final center = _point(p.gridX, p.gridY) - Offset(0, k * _cell * 1.6);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: alpha),
            fontSize: _cell * scale,
            fontWeight: FontWeight.w900,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }
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
  Offset pos = Offset.zero;
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

class _CellFlash {
  _CellFlash({required this.x, required this.y});
  static const double duration = 0.35;
  final int x;
  final int y;
  double age = 0;
}
