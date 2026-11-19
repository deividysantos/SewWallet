import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/catalog.dart';
import '../widgets/common.dart';
import '../widgets/preferred_filter.dart';

/// Filtros preferidos de cada relatório e do painel: ver o que cada um guarda e remover.
/// Para salvar, use o botão ★ na tela do relatório.
class SavedFiltersScreen extends StatelessWidget {
  const SavedFiltersScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedFiltersScreen()));

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<Catalog>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Filtros salvos')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Cada relatório pode ter um filtro preferido, que abre sozinho ao entrar na tela. '
              'Para salvar, toque na ★ no topo do relatório.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (final e in reportFilterTitles.entries)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: Icon(catalog.preferred(e.key) != null ? Icons.star : Icons.star_border),
                title: Text(e.value),
                subtitle: Text(
                  catalog.preferred(e.key) == null
                      ? 'Sem filtro preferido'
                      : describeFilter(e.key, catalog.preferred(e.key)!, catalog).join(' · '),
                ),
                trailing: catalog.preferred(e.key) == null
                    ? null
                    : IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirm(
                            context,
                            title: 'Remover filtro preferido',
                            message: '${e.value} volta a abrir com os filtros padrão.',
                            confirmLabel: 'Remover',
                            destructive: true,
                          );
                          if (!ok) return;
                          try {
                            await catalog.clearPreferred(e.key);
                          } catch (err) {
                            if (context.mounted) showSnack(context, err.toString());
                          }
                        },
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Resumo legível do que um filtro salvo guarda.
List<String> describeFilter(String report, Map<String, dynamic> p, Catalog catalog) {
  final out = <String>[];
  String names(Set<String> ids, String Function(String) nameOf, String plural) =>
      ids.length == 1 ? nameOf(ids.first) : '${ids.length} $plural';

  final accounts = filterIds(p, 'accountIds');
  final cards = filterIds(p, 'cardIds');
  switch (report) {
    case 'cashflow':
      out.add(switch (filterString(p, 'gran')) {
        'day' => 'Por dia',
        'week' => 'Por semana',
        _ => 'Por mês',
      });
      out.add(filterBool(p, 'cumulative') == false ? 'Só o período' : 'Acumulado');
      out.add(filterBool(p, 'projected') == false ? 'Realizado' : 'Previsto');
    case 'categories':
      out.add(filterBool(p, 'income') == true ? 'Receitas' : 'Despesas');
      out.add(filterBool(p, 'yearView') == true ? 'Por ano' : 'Por mês');
      out.add(filterBool(p, 'realized') == true ? 'Realizado' : 'Previsto');
      if (filterBool(p, 'byPayment') == true) out.add('Cartão pelo vencimento');
    case 'forecasts':
      final t = filterString(p, 'type');
      out.add(
        t == 'income'
            ? 'A receber'
            : t == 'expense'
            ? 'A pagar'
            : 'A pagar e a receber',
      );
      final s = filterString(p, 'state');
      if (s != null && s != 'all') {
        out.add(switch (s) {
          'open' => 'Abertas',
          'closed' => 'Encerradas',
          _ => 'Expiradas',
        });
      }
    case 'counterparts':
      final t = filterString(p, 'type');
      out.add(
        t == 'income'
            ? 'A receber de volta'
            : t == 'expense'
            ? 'A devolver'
            : 'Todas',
      );
      final s = filterString(p, 'status');
      if (s == 'pending') out.add('Só pendentes');
      if (s == 'paid') out.add('Só quitadas');
    case 'dashboard':
      out.add(filterBool(p, 'counterparts') == false ? 'Sem contrapartidas' : 'Com contrapartidas');
  }
  if (const {'cashflow', 'categories', 'dashboard'}.contains(report)) {
    if (filterBool(p, 'forecasts') == false) out.add('Sem previsões');
  }
  if (accounts.isNotEmpty) out.add(names(accounts, (id) => catalog.account(id)?.name ?? 'conta', 'contas'));
  if (cards.isNotEmpty) out.add(names(cards, (id) => catalog.card(id)?.name ?? 'cartão', 'cartões'));
  if (accounts.isEmpty && cards.isEmpty && report != 'categories') out.add('Todas as contas');
  return out;
}
