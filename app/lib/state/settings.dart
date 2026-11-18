import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// Em que dia as compras no cartão aparecem na lista de lançamentos.
enum CardDateView {
  /// Na data da compra.
  purchase,

  /// No vencimento da fatura (quando o dinheiro sai: fluxo de caixa).
  payment,
}

/// Preferências do app, salvas no aparelho.
class AppSettings extends ChangeNotifier {
  static const _kCardDateView = 'settings.cardDateView';

  CardDateView cardDateView = CardDateView.purchase;

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kCardDateView);
      cardDateView = CardDateView.values.where((e) => e.name == v).firstOrNull ?? CardDateView.purchase;
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
