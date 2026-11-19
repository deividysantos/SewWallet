import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'cashflow_report_screen.dart';
import 'category_report_screen.dart';
import 'counterpart_report_screen.dart';
import 'forecast_report_screen.dart';
import 'saved_filters_screen.dart';

/// Um relatório disponível na aba Relatórios.
class _ReportEntry {
  const _ReportEntry({required this.title, required this.description, required this.icon, required this.open});

  final String title;
  final String description;
  final IconData icon;
  final Future<void> Function(BuildContext) open;
}

/// Novos relatórios entram nesta lista.
final _reports = <_ReportEntry>[
  _ReportEntry(
    title: 'Por categoria',
    description: 'Quanto foi gasto (ou recebido) em cada categoria, comparado ao período anterior',
    icon: Icons.donut_large,
    open: CategoryReportScreen.open,
  ),
  _ReportEntry(
    title: 'Fluxo de caixa',
    description: 'Entradas, saídas e saldo por dia, semana ou mês',
    icon: Icons.show_chart,
    open: CashflowReportScreen.open,
  ),
  _ReportEntry(
    title: 'Previsões',
    description: 'Previsões do mês (fixas e avulsas): quanto foi previsto, abatido e quanto ainda falta',
    icon: Icons.insights_outlined,
    open: ForecastReportScreen.open,
  ),
  _ReportEntry(
    title: 'Contrapartidas',
    description: 'Compras para outras pessoas: quanto falta receber de volta e quanto já voltou',
    icon: Icons.compare_arrows,
    open: CounterpartReportScreen.open,
  ),
];

/// Aba Relatórios: lista os relatórios disponíveis.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios'),
        actions: [
          IconButton(
            tooltip: 'Filtros salvos',
            onPressed: () => SavedFiltersScreen.open(context),
            icon: const Icon(Icons.bookmarks_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final r in _reports)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: IconBadge(icon: r.icon, color: FinanceColors.of(context).accent, radius: 20),
                title: Text(r.title),
                subtitle: Text(r.description),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => r.open(context),
              ),
            ),
        ],
      ),
    );
  }
}
