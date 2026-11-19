import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// Como as compras no cartão aparecem na lista de lançamentos.
enum CardDateView {
  /// Pela data do pagamento: um lançamento de fatura por cartão, no vencimento
  /// (as compras ficam no detalhe da fatura).
  invoice,

  /// Cada compra na data da compra.
  purchase,
}

/// Preferências do app, salvas no aparelho.
class AppSettings extends ChangeNotifier {
  static const _kCardDateView = 'settings.cardDateView';

  static const _kIncludeForecasts = 'settings.includeForecasts';

  CardDateView cardDateView = CardDateView.invoice;

  /// Valor inicial do "Considerar previsões" na lista e nos relatórios.
  bool includeForecasts = true;

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // "payment" (versões antigas: compras soltas no vencimento) virou a visão agrupada.
      cardDateView = prefs.getString(_kCardDateView) == 'purchase' ? CardDateView.purchase : CardDateView.invoice;
      includeForecasts = prefs.getBool(_kIncludeForecasts) ?? true;
    } catch (_) {
      // Sem armazenamento: fica no padrão.
    }
  }

  Future<void> setCardDateView(CardDateView v) async {
    if (v == cardDateView) return;
    cardDateView = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCardDateView, v.name);
    } catch (_) {}
  }

  Future<void> setIncludeForecasts(bool v) async {
    if (v == includeForecasts) return;
    includeForecasts = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIncludeForecasts, v);
    } catch (_) {}
  }
}
