import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/catalog.dart';
import '../state/notification_reader.dart';
import '../widgets/stitch.dart';
import 'accounts_screen.dart';
import 'cards_screen.dart';
import 'dashboard_screen.dart';
import 'reports_screen.dart';
import 'transactions_screen.dart';

/// Navegação principal (abas na parte de baixo).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    context.read<Catalog>().refresh();
    // Notificações de banco que ficaram na fila do celular (sem conexão) vão agora.
    NotificationReader.flush();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [DashboardScreen(), TransactionsScreen(), AccountsScreen(), CardsScreen(), ReportsScreen()],
      ),
      bottomNavigationBar: ColoredBox(
        color: Theme.of(context).navigationBarTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pesponto separando o conteúdo da barra.
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 3),
            const Stitch(indent: 12, endIndent: 12),
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Início',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Lançamentos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_outlined),
                  selectedIcon: Icon(Icons.account_balance),
                  label: 'Contas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.credit_card_outlined),
                  selectedIcon: Icon(Icons.credit_card),
                  label: 'Cartões',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: 'Relatórios',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
