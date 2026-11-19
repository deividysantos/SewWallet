import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/stitch.dart';
import 'card_detail_screen.dart';
import 'card_form.dart';

String invoiceStatusLabel(InvoiceStatus s) => switch (s) {
  InvoiceStatus.open => 'Aberta',
  InvoiceStatus.closed => 'Fechada',
  InvoiceStatus.paid => 'Paga',
  InvoiceStatus.overdue => 'Atrasada',
};

Color invoiceStatusColor(BuildContext context, InvoiceStatus s) {
  final colors = FinanceColors.of(context);
  final scheme = Theme.of(context).colorScheme;
  return switch (s) {
    InvoiceStatus.open => scheme.primary,
    InvoiceStatus.closed => scheme.onSurfaceVariant,
    InvoiceStatus.paid => colors.income,
    InvoiceStatus.overdue => colors.warning,
  };
}

/// Cartões com a fatura atual e o limite usado.
class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<Catalog>();
    final active = catalog.activeCards;
    final archived = catalog.cards.where((c) => c.archived).toList();

    Widget body;
    if (!catalog.loaded && catalog.error != null) {
      body = ErrorView(message: catalog.error!, onRetry: catalog.refresh);
    } else if (!catalog.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (catalog.cards.isEmpty) {
      body = EmptyView(
        icon: Icons.credit_card,
        message: 'Nenhum cartão ainda.',
        action: FilledButton.icon(
          onPressed: catalog.activeAccounts.isEmpty ? null : () => CardForm.open(context),
          icon: const Icon(Icons.add),
          label: Text(catalog.activeAccounts.isEmpty ? 'Cadastre uma conta antes' : 'Novo cartão'),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: catalog.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            for (final c in active) _CardTile(card: c),
            if (archived.isNotEmpty)
              ExpansionTile(
                title: Text('Arquivados (${archived.length})'),
                children: [for (final c in archived) _CardTile(card: c)],
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Cartões')),
      body: body,
      floatingActionButton: catalog.activeAccounts.isEmpty
          ? null
          : FloatingActionButton(
              heroTag: null, // várias abas com "+" na mesma rota
              tooltip: 'Novo cartão',
              onPressed: () => CardForm.open(context),
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card});

  final CardInfo card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = FinanceColors.of(context);
    final inv = card.currentInvoice;
    final color = hexColor(card.color) ?? scheme.primary;
    final muted = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final limit = card.limit;
    final usedRatio = limit == null || limit == 0 ? null : (card.limitUsed / limit).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => CardDetailScreen.open(context, cardId: card.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pesponto na cor do cartão.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Stitch(color: color.withValues(alpha: 0.8), indent: 14, endIndent: 14),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBadge(icon: Icons.credit_card, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.name,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text('Fecha dia ${card.closingDay} · vence dia ${card.dueDay}', style: muted),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fatura atual · vence ${shortDate(inv.dueDate)}',
                              style: muted,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              money(inv.total),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: colors.expense,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(invoiceStatusLabel(inv.status)),
                        labelStyle: TextStyle(color: invoiceStatusColor(context, inv.status)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (usedRatio != null) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: usedRatio,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                      color: usedRatio > 0.9 ? colors.expense : color,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Limite: usado ${money(card.limitUsed)} de ${money(limit!)} · disponível ${money(card.limitAvailable ?? 0)}',
                      style: muted,
                    ),
                  ] else if (card.limitUsed > 0) ...[
                    const SizedBox(height: 8),
                    Text('Em aberto (com parcelas futuras): ${money(card.limitUsed)}', style: muted),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
