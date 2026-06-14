import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/components/control_pad.dart';
import '../../core/input/control_scheme.dart';
import '../../core/storage/game_storage.dart';

/// Пикер схемы управления для одной игры: сверху живое превью-«телефон» с
/// выбранным контролом, ниже — чипы выбора и описание. Выбор применяется и
/// сохраняется сразу ([GameStorage]); в игре подхватывается при следующем входе.
///
/// UX скопирован с экрана «Стиль навигации» из проекта blood_pressure_diary,
/// но состояние — на наших `GameStorage` + setState (без BLoC).
class ControlPickerScreen extends StatefulWidget {
  const ControlPickerScreen({
    super.key,
    required this.gameId,
    required this.title,
    required this.accent,
    required this.schemes,
  });

  final String gameId;
  final String title;
  final Color accent;
  final List<ControlScheme> schemes;

  @override
  State<ControlPickerScreen> createState() => _ControlPickerScreenState();
}

class _ControlPickerScreenState extends State<ControlPickerScreen> {
  late ControlScheme _scheme =
      GameStorage.instance.controlScheme(widget.gameId);

  void _select(ControlScheme s) {
    if (s == _scheme) return;
    HapticFeedback.selectionClick();
    setState(() => _scheme = s);
    GameStorage.instance.setControlScheme(widget.gameId, s);
  }

  @override
  Widget build(BuildContext context) {
    final systemBottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      appBar: AppBar(title: Text('Управление · ${widget.title}')),
      body: Column(
        children: [
          // Живое превью выбранной схемы.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: _ControlPreview(
                    key: ValueKey(_scheme),
                    scheme: _scheme,
                    accent: widget.accent,
                  ),
                ),
              ),
            ),
          ),
          // Чипы выбора схемы.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final s in widget.schemes)
                  _SchemeChip(
                    scheme: s,
                    accent: widget.accent,
                    selected: s == _scheme,
                    onTap: () => _select(s),
                  ),
              ],
            ),
          ),
          // Описание выбранной схемы.
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _scheme.description,
                key: ValueKey(_scheme),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          SizedBox(height: 22 + systemBottom),
        ],
      ),
    );
  }
}

/// Чип выбора схемы: пилюля; у выбранного — заливка акцентом + галочка,
/// у остальных — эмодзи схемы.
class _SchemeChip extends StatelessWidget {
  const _SchemeChip({
    required this.scheme,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final ControlScheme scheme;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
          border: Border.all(
            color: selected ? accent : const Color(0x24FFFFFF),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_circle, size: 18, color: accent),
              const SizedBox(width: 6),
            ] else ...[
              Text(scheme.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
            ],
            Text(
              scheme.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accent : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Мини-«телефон» с условным полем игры и выбранным контролом внизу
/// (или подсказкой про свайпы для схемы «Жесты»). Неинтерактивен.
class _ControlPreview extends StatelessWidget {
  const _ControlPreview({
    super.key,
    required this.scheme,
    required this.accent,
  });

  final ControlScheme scheme;
  final Color accent;

  static const double _vw = 300;
  static const double _vh = 600;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: Container(
        width: _vw,
        height: _vh,
        decoration: BoxDecoration(
          color: const Color(0xFF0E0B1A),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: _FauxBoard(accent: accent)),
            if (scheme == ControlScheme.gestures)
              const Positioned.fill(child: _SwipeHint())
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                // Внутри фейкового телефона обнуляем системные отступы — иначе
                // SafeArea в ControlOverlay добавит реальный нижний инсет и
                // крестовина наедет на «поле» (в самой игре этого нет).
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                    viewInsets: EdgeInsets.zero,
                  ),
                  child: IgnorePointer(
                    child: ControlOverlay(
                      scheme: scheme,
                      accent: accent,
                      onDir: _noop,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static void _noop(PadDir _) {}
}

/// Условное «поле игры» — шапка-полоски + доска с парой ячеек акцентом.
class _FauxBoard extends StatelessWidget {
  const _FauxBoard({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w) => Container(
          width: w,
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(5),
          ),
        );
    Widget cell(Color c) => Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(7),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [bar(54), bar(40)],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161126),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    cell(accent),
                    cell(accent.withValues(alpha: 0.8)),
                    cell(accent.withValues(alpha: 0.6)),
                    cell(const Color(0xFFFF6FAE)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 190),
        ],
      ),
    );
  }
}

/// Подсказка для схемы «Жесты»: иконка свайпа + подпись по центру.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, 0.4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swipe_rounded,
              size: 56, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            'свайп по экрану',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
