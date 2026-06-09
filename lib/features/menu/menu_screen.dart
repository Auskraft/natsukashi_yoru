import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/legal/legal_screens.dart';
import '../../core/storage/game_storage.dart';
import 'game_catalog.dart';

// ── Палитра лобби (из дизайн-хэндоффа V2) ────────────────────────────────────
const _bg = Color(0xFF07051A);
const _textPrimary = Color(0xFFF1F0FF);
const _textSecondary = Color(0xFF7060A0);
const _textMuted = Color(0xFF3A3260);

/// Лобби: тёмный фон с анимированным звёздным небом (по всему экрану) и
/// прокручиваемый список карточек игр. Обновляется при возврате из игры.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen>
    with SingleTickerProviderStateMixin {
  late final List<_Star> _stars = _generateStars();
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  List<_Star> _generateStars() {
    final rng = Random(7); // стабильное небо
    return List.generate(60, (_) {
      return _Star(
        dx: rng.nextDouble(),
        dy: rng.nextDouble(),
        r: 0.4 + rng.nextDouble() * 1.5,
        opacity: 0.35 + rng.nextDouble() * 0.65,
        phase: rng.nextDouble(),
        speed: 0.5 + rng.nextDouble() * 1.5, // мерцаний за цикл
      );
    });
  }

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  Future<void> _open(GameEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: entry.builder),
    );
    if (mounted) setState(() {}); // подтянуть свежие рекорды
  }

  @override
  Widget build(BuildContext context) {
    final storage = GameStorage.instance;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Анимированное звёздное небо по всему экрану + верхнее свечение.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _twinkle,
              builder: (_, _) => CustomPaint(
                painter: _SkyPainter(_stars, _twinkle.value),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Header(),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    itemCount: kGameCatalog.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      if (i == kGameCatalog.length) {
                        return _DocsFooter(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const DocsScreen(),
                            ),
                          ),
                        );
                      }
                      final entry = kGameCatalog[i];
                      return _GameCard(
                        entry: entry,
                        record: _recordLabel(entry, storage),
                        onTap: () => _open(entry),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Подпись рекорда по типу метрики игры (или null, если рекорда ещё нет).
  String? _recordLabel(GameEntry e, GameStorage s) {
    switch (e.metric) {
      case GameMetric.score:
        final v = s.highScore(e.id);
        return v > 0 ? '$v' : null;
      case GameMetric.time:
        final t = s.bestTime(e.id);
        if (t <= 0) return null;
        return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
      case GameMetric.moves:
        final m = s.bestTime(e.id);
        return m > 0 ? '$m ход.' : null;
    }
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'なつかしい夜',
            style: GoogleFonts.notoSansJp(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: _textMuted,
            ),
          ),
          Text(
            'Выбери игру',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1,
              color: _textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Пункт «Документы · О приложении» внизу списка игр.
class _DocsFooter extends StatelessWidget {
  const _DocsFooter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x08FFFFFF),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              const Text('📄', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Документы · О приложении',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _textSecondary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: _textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.entry,
    required this.record,
    required this.onTap,
  });

  final GameEntry entry;
  final String? record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: entry.accent.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x0AFFFFFF), Color(0x02FFFFFF)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Row(
              children: [
                _IconBlock(icon: entry.icon, accent: entry.accent),
                Expanded(child: _CardContent(entry: entry, record: record)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBlock extends StatelessWidget {
  const _IconBlock({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.14), accent.withValues(alpha: 0.03)],
        ),
        border: Border(
          right: BorderSide(color: accent.withValues(alpha: 0.14)),
        ),
      ),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.45),
                blurRadius: 16,
              ),
            ],
          ),
          child: Icon(icon, size: 30, color: accent),
        ),
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({required this.entry, required this.record});

  final GameEntry entry;
  final String? record;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.nameJp,
                style: GoogleFonts.notoSansJp(
                  fontSize: 10.5,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                entry.difficulty.label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: entry.difficulty.color,
                ),
              ),
              const SizedBox(width: 12),
              if (record != null) ...[
                Text(
                  'HS',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: _textMuted,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  record!,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: entry.accent,
                  ),
                ),
              ] else
                Text(
                  'ещё не играл',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    color: _textMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Одна звезда фона (нормализованные координаты 0..1 по всему экрану).
class _Star {
  const _Star({
    required this.dx,
    required this.dy,
    required this.r,
    required this.opacity,
    required this.phase,
    required this.speed,
  });
  final double dx;
  final double dy;
  final double r;
  final double opacity;
  final double phase;
  final double speed;
}

/// Рисует верхнее радиальное свечение и анимированное звёздное небо.
/// [t] — фаза анимации 0..1 (мерцание + лёгкий дрейф вниз).
class _SkyPainter extends CustomPainter {
  _SkyPainter(this.stars, this.t);

  final List<_Star> stars;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Верхнее фиолетовое свечение.
    final glowRect = Rect.fromCenter(
      center: Offset(size.width / 2, -20),
      width: 340,
      height: 260,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 280),
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0x2B6D28D9), const Color(0x006D28D9)],
        ).createShader(glowRect),
    );

    // Звёзды: мерцание (синус по фазе) + медленный дрейф вниз с заворотом.
    final paint = Paint();
    for (final s in stars) {
      final twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(2 * pi * (s.phase + t * s.speed)));
      final y = ((s.dy + t * 0.06) % 1.0) * size.height;
      paint.color = Colors.white.withValues(alpha: s.opacity * twinkle);
      canvas.drawCircle(Offset(s.dx * size.width, y), s.r, paint);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => oldDelegate.t != t;
}
