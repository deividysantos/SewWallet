import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// Como as compras no cartão aparecem na lista de lançamentos.
enum CardDateView {
  /// Agrupadas: um lançamento de fatura por cartão, no vencimento (as compras ficam no detalhe da fatura).
  invoice,

  /// Cada compra na data da compra.
  purchase,

  /// Cada compra no vencimento da fatura (quando o dinheiro sai: fluxo de caixa).
  payment,
}

/// Preferências do app, salvas no aparelho.
class AppSettings extends ChangeNotifier {
  static const _kCardDateView = 'settings.cardDateView';

  CardDateView cardDateView = CardDateView.invoice;

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kCardDateView);
      cardDateView = CardDateView.values.where((e) => e.name == v).firstOrNull ?? CardDateView.invoice;
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
}
