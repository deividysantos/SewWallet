import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/saved_filters_screen.dart';
import '../state/catalog.dart';
import 'common.dart';

/// Nome de cada tela que tem filtro preferido.
const reportFilterTitles = {
  'dashboard': 'Início (painel do mês)',
  'cashflow': 'Fluxo de caixa',
  'categories': 'Por categoria',
  'forecasts': 'Previsões',
  'counterparts': 'Contrapartidas',
};

/// Lista de ids salva no filtro (aceita ausência e lixo).
Set<String> filterIds(Map<String, dynamic> p, String key) => {
  for (final v in (p[key] as List?) ?? const [])
    if (v is String) v,
};

bool? filterBool(Map<String, dynamic> p, String key) => p[key] is bool ? p[key] as bool : null;

String? filterString(Map<String, dynamic> p, String key) => p[key] is String ? p[key] as String : null;

/// Botão ★ da barra do relatório: salvar os filtros atuais como preferidos (abrem sozinhos
/// da próxima vez), aplicar ou remover o preferido, e abrir a tela de filtros salvos.
class PreferredFilterButton extends StatelessWidget {
  const PreferredFilterButton({super.key, required this.report, required this.current, required this.apply});

  final String report;

  /// Filtros atuais da tela (sem o período).
  final Map<String, dynamic> Function() current;

  /// Aplica um filtro salvo na tela.
  final void Function(Map<String, dynamic>) apply;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<Catalog>();
    final saved = catalog.preferred(report);
    return PopupMenuButton<String>(
      key: const ValueKey('preferredFilter'),
      tooltip: 'Filtro preferido',
      icon: Icon(saved != null ? Icons.star : Icons.star_border),
      onSelected: (v) async {
        try {
          switch (v) {
            case 'save':
              await catalog.savePreferred(report, current());
              if (context.mounted) showSnack(context, 'Filtro preferido salvo: abre assim da próxima vez');
            case 'apply':
              apply(saved!);
            case 'clear':
              await catalog.clearPreferred(report);
              if (context.mounted) showSnack(context, 'Filtro preferido removido');
            case 'manage':
              await SavedFiltersScreen.open(context);
          }
        } catch (e) {
          if (context.mounted) showSnack(context, e.toString());
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'save',
          child: ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(saved == null ? 'Salvar como filtro preferido' : 'Trocar o preferido pelos filtros atuais'),
          ),
        ),
        if (saved != null) ...[
          const PopupMenuItem(
            value: 'apply',
            child: ListTile(leading: Icon(Icons.filter_alt_outlined), title: Text('Aplicar filtro preferido')),
          ),
          const PopupMenuItem(
            value: 'clear',
            child: ListTile(leading: Icon(Icons.star_border), title: Text('Remover filtro preferido')),
          ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'manage',
          child: ListTile(leading: Icon(Icons.bookmarks_outlined), title: Text('Filtros salvos')),
        ),
      ],
    );
  }
}
