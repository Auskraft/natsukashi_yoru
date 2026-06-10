import 'package:url_launcher/url_launcher.dart';

/// Оценка приложения (рейтинг-гейт): 4–5★ ведут на страницу RuStore,
/// 1–3★ — на почту обратной связи. Само приложение в сеть не ходит —
/// ссылка/почта открываются внешним приложением (браузер/почтовый клиент).
class RatingService {
  RatingService._();
  static final RatingService instance = RatingService._();

  static const _storeUrl =
      'https://www.rustore.ru/catalog/app/com.auskraft.natsukashi_yoru';
  static const _email = 'auskraft@gmail.com';

  Future<void> openStore() async {
    await launchUrl(
      Uri.parse(_storeUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> openEmail() async {
    final subject = Uri.encodeComponent('Natsukashi Yoru — отзыв');
    await launchUrl(Uri.parse('mailto:$_email?subject=$subject'));
  }
}
