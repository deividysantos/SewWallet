import 'package:flutter/material.dart';

import '../models/ledger.dart';
import '../screens/transaction_form.dart';
import '../theme.dart';

/// Botão "+" que se abre em atalhos: despesa (↓), receita (↑), transferência (⇄) e compra no
/// cartão. O "+" some enquanto os atalhos estão abertos; tocar fora (ou no ✕) fecha.
class NewTransactionFab extends StatefulWidget {
  const NewTransactionFab({super.key});

  @override
  State<NewTransactionFab> createState() => _NewTransactionFabState();
}

class _NewTransactionFabState extends State<NewTransactionFab> {
  bool _open = false;

  Future<void> _start(TxType type, {bool card = false}) async {
    setState(() => _open = false);
    await TransactionForm.open(context, type: type, card: card);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (!_open) {
      return FloatingActionButton(
        key: const ValueKey('newTx'),
        // O Início e Lançamentos têm cada um o seu "+" na mesma rota (abas): sem animação Hero compartilhada.
        heroTag: null,
        tooltip: 'Novo lançamento',
        onPressed: () => setState(() => _open = true),
        child: const Icon(Icons.add),
      );
    }

    Widget action(String label, IconData icon, Color color, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: scheme.surfaceContainerHigh,
            elevation: 2,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
          const SizedBox(width: 10),
          FloatingActionButton.small(
            heroTag: null,
            tooltip: label,
            backgroundColor: color,
            foregroundColor: Colors.white,
            onPressed: onTap,
            child: Icon(icon),
          ),
        ],
      ),
    );

    return TapRegion(
      onTapOutside: (_) => setState(() => _open = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          action('Despesa', Icons.arrow_downward, colors.expense, () => _start(TxType.expense)),
          action('Receita', Icons.arrow_upward, colors.income, () => _start(TxType.income)),
          action('Transferência', Icons.compress, scheme.primary, () => _start(TxType.transfer)),
          action('Cartão', Icons.credit_card, colors.accent, () => _start(TxType.expense, card: true)),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: null,
            tooltip: 'Fechar',
            onPressed: () => setState(() => _open = false),
            child: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
