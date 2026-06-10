import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'rating_service.dart';

const _bg = Color(0xFF0E0B1A);
const _border = Color(0x14FFFFFF);
const _textPrimary = Color(0xFFF1F0FF);
const _textMuted = Color(0xFF7060A0);
const _gold = Color(0xFFFFD54F);

/// Показать нижнюю плашку «Оцените приложение» со звёздами.
Future<void> showRateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _RateSheet(),
  );
}

class _RateSheet extends StatefulWidget {
  const _RateSheet();

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  int _selected = 0;
  bool _acting = false;

  Future<void> _pick(int stars) async {
    if (_acting) return;
    setState(() {
      _selected = stars;
      _acting = true;
    });

    if (stars == 5) {
      // Праздничный отклик: тройной убывающий «бззз».
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 120), HapticFeedback.mediumImpact);
      Future.delayed(const Duration(milliseconds: 240), HapticFeedback.lightImpact);
    } else {
      HapticFeedback.selectionClick();
    }

    // Даём звёздам доиграть (на 5★ — каскад подлиннее).
    await Future.delayed(Duration(milliseconds: stars == 5 ? 950 : 400));
    if (!mounted) return;
    Navigator.pop(context);
    if (stars >= 4) {
      await RatingService.instance.openStore();
    } else {
      await RatingService.instance.openEmail();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: _border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Оцените приложение',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Оценка помогает другим найти приложение',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textMuted, height: 1.4),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final n = i + 1;
              final filled = n <= _selected;
              final star = Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 40,
                color: filled ? _gold : _textMuted.withValues(alpha: 0.5),
              );
              // Заполненные звёзды «выстреливают» с упругим отскоком,
              // со сдвигом по индексу — каскад слева направо.
              final child = filled
                  ? TweenAnimationBuilder<double>(
                      key: ValueKey('pop-$_selected-$i'),
                      tween: Tween(begin: 0.4, end: 1.0),
                      duration: Duration(milliseconds: 320 + i * 110),
                      curve: Curves.elasticOut,
                      builder: (_, v, c) => Transform.scale(scale: v, child: c),
                      child: star,
                    )
                  : star;
              return GestureDetector(
                onTap: () => _pick(n),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: child,
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Text(
                'Позже',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
