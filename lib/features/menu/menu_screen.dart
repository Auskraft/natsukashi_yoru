import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/storage/game_storage.dart';
import 'game_catalog.dart';

// ── Палитра лобби (из дизайн-хэндоффа V2) ────────────────────────────────────
const _bg = Color(0xFF07051A);
const _textPrimary = Color(0xFFF1F0FF);
const _textSecondary = Color(0xFF7060A0);
const _textMuted = Color(0xFF3A3260);
const _orange = Color(0xFFFB923C);

/// Лобби: тёмный фон со звёздным небом, хедер с дневным стриком и
/// прокручиваемый список карточек игр. Обновляется при возврате из игры.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  late final List<_Star> _stars = _generateStars();

  List<_Star> _generateStars() {
    final rng = Random(7); // стабильное небо
    return List.generate(34, (_) {
      return _Star(
        dx: rng.nextDouble(),
        dy: rng.nextDouble(),
        r: 0.4 + rng.nextDouble() * 1.3,
        opacity: 0.4 + rng.nextDouble() * 0.6,
      );
    });
  }

  Future<void> _open(GameEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: entry.builder),
    );
    if (mounted) setState(() {}); // подтянуть свежие рекорды/стрик
  }

  @override
  Widget build(BuildContext context) {
    final storage = GameStorage.instance;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Звёздное небо + верхнее свечение (декор).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 220,
            child: CustomPaint(painter: _SkyPainter(_stars)),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(streak: storage.streak),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    itemCount: kGameCatalog.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
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
  const _Header({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
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
          ),
          if (streak > 0) _StreakPill(days: streak),
        ],
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: const Color(0x1CF97316),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x3DF97316)),
      ),
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 5),
          Text(
            '$days',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _orange,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            'дней',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6A4020),
            ),
          ),
        ],
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

/// Одна звезда фона (нормализованные координаты 0..1 по области неба).
class _Star {
  const _Star({
    required this.dx,
    required this.dy,
    required this.r,
    required this.opacity,
  });
  final double dx;
  final double dy;
  final double r;
  final double opacity;
}

/// Рисует верхнее радиальное свечение и статичное звёздное небо.
class _SkyPainter extends CustomPainter {
  _SkyPainter(this.stars);

  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    // Верхнее фиолетовое свечение.
    final glowRect = Rect.fromCenter(
      center: Offset(size.width / 2, -20),
      width: 340,
      height: 240,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0x2B6D28D9),
            const Color(0x006D28D9),
          ],
        ).createShader(glowRect),
    );

    // Звёзды.
    final star = Paint()..color = Colors.white;
    for (final s in stars) {
      star.color = Colors.white.withValues(alpha: s.opacity);
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), s.r, star);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => false;
}
