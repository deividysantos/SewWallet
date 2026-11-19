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

  /// Filtro preferido de cada relatório (chave: cashflow, categories, forecasts, counterparts, dashboard).
  Map<String, Map<String, dynamic>> preferredFilters = {};

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
    preferredFilters = {};
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
    await _loadFilters();
    revision++;
    notifyListeners();
  }

  /// Os filtros preferidos não impedem o app de abrir se falharem.
  Future<void> _loadFilters() async {
    try {
      final list = await _session.api.get('/report-filters') as List;
      preferredFilters = {
        for (final j in list.cast<Map<String, dynamic>>())
          j['report'] as String: Map<String, dynamic>.from(j['params'] as Map),
      };
    } catch (_) {}
  }

  Map<String, dynamic>? preferred(String report) => preferredFilters[report];

  /// Salva [params] como o filtro preferido de [report] (sem recarregar as telas).
  Future<void> savePreferred(String report, Map<String, dynamic> params) async {
    await _session.api.put('/report-filters/$report', {'params': params});
    preferredFilters = {...preferredFilters, report: params};
    notifyListeners();
  }

  Future<void> clearPreferred(String report) async {
    await _session.api.delete('/report-filters/$report');
    preferredFilters = {...preferredFilters}..remove(report);
    notifyListeners();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }
}
