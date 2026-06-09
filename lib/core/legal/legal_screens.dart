import 'package:flutter/material.dart';

import '../components/overlay_kit.dart';
import 'legal_docs.dart';

// Палитра — в стиле лобби (хэндофф V2).
const _bg = Color(0xFF07051A);
const _surface = Color(0x0FFFFFFF);
const _border = Color(0x14FFFFFF);
const _textPrimary = Color(0xFFF1F0FF);
const _textMuted = Color(0xFF7060A0);
const _accent = Color(0xFFA78BFA);

/// Версия приложения для блока «О приложении» (синхронно с pubspec version).
const String _appVersion = '1.0.0';

/// Просмотр одного юридического документа: шапка с кнопкой назад + текст.
class LegalDocScreen extends StatelessWidget {
  const LegalDocScreen({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: title),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: _textPrimary,
                    height: 1.55,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Меню документов: соглашение, политика конфиденциальности, обработка ПДн,
/// плюс блок «О приложении». Открывается из лобби (внизу списка игр).
class DocsScreen extends StatelessWidget {
  const DocsScreen({super.key});

  void _open(BuildContext context, String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocScreen(title: title, body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(title: 'Документы'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _DocsCard(
                    children: [
                      _DocRow(
                        emoji: '📄',
                        title: 'Пользовательское соглашение',
                        onTap: () => _open(context,
                            'Пользовательское соглашение', kTermsOfUse),
                      ),
                      const _RowDivider(),
                      _DocRow(
                        emoji: '🔒',
                        title: 'Политика конфиденциальности',
                        onTap: () => _open(context,
                            'Политика конфиденциальности', kPrivacyPolicy),
                      ),
                      const _RowDivider(),
                      _DocRow(
                        emoji: '📋',
                        title: 'Обработка персональных данных',
                        onTap: () => _open(context,
                            'Обработка персональных данных', kDataProcessing),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _AboutCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Экран согласия при первом запуске: ссылки на документы + кнопка принятия.
class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key, required this.onAccept});

  final VoidCallback onAccept;

  void _open(BuildContext context, String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocScreen(title: title, body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              const Text('🌙', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              const Text(
                kAppLegalName,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Сборник мини-игр. Прогресс хранится на вашем устройстве.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _textMuted, height: 1.5),
              ),
              const SizedBox(height: 24),
              _DocsCard(
                children: [
                  _DocRow(
                    emoji: '📄',
                    title: 'Пользовательское соглашение',
                    onTap: () => _open(
                        context, 'Пользовательское соглашение', kTermsOfUse),
                  ),
                  const _RowDivider(),
                  _DocRow(
                    emoji: '🔒',
                    title: 'Политика конфиденциальности',
                    onTap: () => _open(
                        context, 'Политика конфиденциальности', kPrivacyPolicy),
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                'Продолжая, вы принимаете Пользовательское соглашение и Политику конфиденциальности.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: _textMuted, height: 1.4),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: PlayButton(label: 'ПРИНЯТЬ И ПРОДОЛЖИТЬ', onTap: onAccept),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Вспомогательные виджеты ──────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            color: _textPrimary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocsCard extends StatelessWidget {
  const _DocsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) => const Divider(height: 1, color: _border);
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.emoji,
    required this.title,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 14, color: _textPrimary),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: _textMuted.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('О приложении',
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: _accent)),
          const SizedBox(height: 10),
          _aboutLine('Название', '$kAppLegalName · なつかしい夜'),
          _aboutLine('Версия', _appVersion),
          _aboutLine('Разработчик', kOperator),
          _aboutLine('Контакт', kContactEmail),
        ],
      ),
    );
  }

  Widget _aboutLine(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(k,
                  style: const TextStyle(fontSize: 12.5, color: _textMuted)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(fontSize: 12.5, color: _textPrimary)),
            ),
          ],
        ),
      );
}
