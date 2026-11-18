import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import '../widgets/stitch.dart';
import 'categories_screen.dart';

/// Configurações do app. Novas parametrizações entram aqui, cada grupo na sua seção.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final theme = Theme.of(context);

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          section('Lançamentos'),
          ListTile(
            title: const Text('Compras no cartão'),
            subtitle: const Text('Como as compras aparecem na lista de lançamentos'),
          ),
          RadioGroup<CardDateView>(
            groupValue: settings.cardDateView,
            onChanged: (v) {
              if (v != null) settings.setCardDateView(v);
            },
            child: const Column(
              children: [
                RadioListTile<CardDateView>(
                  value: CardDateView.invoice,
                  title: Text('Data do pagamento, agrupadas na fatura'),
                  subtitle: Text(
                    'Um lançamento por cartão no vencimento da fatura, no mês em que você paga. '
                    'Toque nele para ver as compras (fluxo de caixa)',
                  ),
                ),
                RadioListTile<CardDateView>(
                  value: CardDateView.purchase,
                  title: Text('Data da compra'),
                  subtitle: Text('Mostra cada compra no dia em que foi feita'),
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Stitch(indent: 16, endIndent: 16)),
          section('Cadastros'),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Categorias'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => CategoriesScreen.open(context),
          ),
          const SizedBox(height: 40),
          const Center(child: SewMark(size: 22)),
          const SizedBox(height: 6),
          Center(
            child: Text('feito sob medida', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
