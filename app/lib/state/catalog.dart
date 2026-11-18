import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../models/ledger.dart';
import 'session.dart';

/// Contas, cartões e categorias do usuário, compartilhados entre as telas.
///
/// Depois de qualquer alteração (lançamento, pagamento, conta...), chame
/// [refresh]: ele recarrega os dados e incrementa [revision], que as telas
/// de lançamentos e relatórios observam para se atualizar.
class Catalog extends ChangeNotifier {
  Catalog(this._session) {
    _session.addListener(_onSession);
    _lastToken = _session.token;
  }

  final Session _session;
  String? _lastToken;

  List<Account> accounts = [];
  List<CardInfo> cards = [];
  List<Category> categories = [];
  bool loaded = false;
  String? error;

  /// Muda a cada recarga; quem depende de saldos recarrega junto.
  int revision = 0;

  List<Account> get activeAccounts => accounts.where((a) => !a.archived).toList();
  List<CardInfo> get activeCards => cards.where((c) => !c.archived).toList();

  Account? account(String? id) => accounts.where((a) => a.id == id).firstOrNull;
  CardInfo? card(String? id) => cards.where((c) => c.id == id).firstOrNull;

  void _onSession() {
    if (_session.token == _lastToken) return;
    _lastToken = _session.token;
    accounts = [];
    cards = [];
    categories = [];
    loaded = false;
    error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!_session.isLoggedIn) return;
    try {
      final api = _session.api;
      final r = await Future.wait([api.get('/accounts'), api.get('/cards'), api.get('/categories')]);
      accounts = [for (final j in r[0] as List) Account.fromJson(j as Map<String, dynamic>)];
      cards = [for (final j in r[1] as List) CardInfo.fromJson(j as Map<String, dynamic>)];
      categories = [for (final j in r[2] as List) Category.fromJson(j as Map<String, dynamic>)];
      loaded = true;
      error = null;
    } catch (e) {
      error = e.toString();
    }
    revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }
}
