import 'package:flutter/material.dart';

import 'cashflow_report_screen.dart';

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
    title: 'Fluxo de caixa',
    description: 'Entradas, saídas e saldo por dia, semana ou mês',
    icon: Icons.show_chart,
    open: CashflowReportScreen.open,
  ),
];

/// Aba Relatórios: lista os relatórios disponíveis.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final r in _reports)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(r.icon),
                ),
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
