import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'card_detail_screen.dart';
import 'categories_screen.dart';
import 'transaction_form.dart';

/// Lançamentos do mês agrupados por dia, com o saldo das contas no fim de cada dia.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  TransactionsPage? _page;
  Set<String> _accountFilter = {};
  bool _includeCards = true;

  bool _loading = true;
  String? _error;
  String? _busyId;
  bool _scrollToToday = true;
  final _todayKey = GlobalKey();
  final _scroll = ScrollController();
  late final Catalog _catalog;
  int _seenRevision = -1;

  @override
  void initState() {
    super.initState();
    _catalog = context.read<Catalog>();
    _seenRevision = _catalog.revision;
    _catalog.addListener(_onCatalog);
    _load();
  }

  /// Algo mudou (lançamento, pagamento, conta...): recarrega os saldos.
  void _onCatalog() {
    if (_catalog.revision == _seenRevision) return;
    _seenRevision = _catalog.revision;
    _load();
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalog);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = DateTime(_month.year, _month.month, 1);
      final to = DateTime(_month.year, _month.month + 1, 0);
      final data = await api.get('/transactions', query: {
        'from': apiDate(from),
        'to': apiDate(to),
        'accountIds': _accountFilter.join(','),
        'includeCards': '$_includeCards',
      });
      if (!mounted) return;
      setState(() => _page = TransactionsPage.fromJson(data as Map<String, dynamic>));
      if (_scrollToToday) {
        _scrollToToday = false;
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToToday());
      }
    } catch (e) {
      if (!mounted) return;
      if (_page == null) {
        setState(() => _error = e.toString());
      } else {
        _snack(e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _jumpToToday() {
    final ctx = _todayKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.02, duration: const Duration(milliseconds: 250));
    } else if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _scrollToToday = true;
    _load();
  }

  void _goToCurrentMonth() {
    final now = DateTime.now();
    if (_month.year == now.year && _month.month == now.month) {
      _jumpToToday();
      return;
    }
    setState(() => _month = DateTime(now.year, now.month));
    _scrollToToday = true;
    _load();
  }

  void _snack(String message) => showSnack(context, message);

  Future<void> _togglePaid(TxItem t) async {
    setState(() => _busyId = t.id);
    try {
      await context.read<Session>().api.patch('/transactions/${t.id}/status', {
        'status': t.paid ? 'PENDING' : 'PAID',
      });
      await _catalog.refresh(); // recarrega esta lista e os saldos das contas
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _payInvoice(InvoiceItem inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pagar fatura'),
        content: Text(
          '${inv.description}\n'
          'Valor: ${money(inv.remaining)}\n'
          'Conta: ${inv.account?.name ?? '-'}\n'
          'Data do pagamento: hoje',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pagar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = inv.id);
    try {
      await context.read<Session>().api.post('/invoices/${inv.id}/payments');
      await _catalog.refresh();
      _snack('Pagamento da fatura lançado');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<(Set<String>, bool)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(
        accounts: _catalog.activeAccounts,
        selected: _accountFilter,
        includeCards: _includeCards,
      ),
    );
    if (result == null) return;
    setState(() {
      _accountFilter = result.$1;
      _includeCards = result.$2;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final catalog = context.watch<Catalog>();
    final filtered = _accountFilter.isNotEmpty || !_includeCards;
    return Scaffold(
      appBar: AppBar(
        title: _MonthSwitcher(
          month: _month,
          onPrevious: () => _changeMonth(-1),
          onNext: () => _changeMonth(1),
          onTapTitle: _goToCurrentMonth,
        ),
        leading: IconButton(
          tooltip: 'Filtros',
          onPressed: catalog.activeAccounts.isEmpty ? null : _openFilters,
          icon: Badge(isLabelVisible: filtered, child: const Icon(Icons.filter_list)),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (v) {
              if (v == 'categories') CategoriesScreen.open(context);
              if (v == 'logout') session.logout();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'categories',
                child: ListTile(
                  leading: Icon(Icons.label_outline),
                  title: Text('Categorias'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sair'),
                  subtitle: session.userName == null ? null : Text(session.userName!),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Novo lançamento',
        onPressed: () => TransactionForm.open(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    final page = _page;
    if (page == null) {
      if (_error != null) {
        return ErrorView(message: _error!, onRetry: _load);
      }
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
            _SummaryCard(page: page),
            if (page.days.every((d) => d.items.isEmpty))
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Nenhum lançamento neste mês', textAlign: TextAlign.center),
              ),
            for (final day in page.days) ...[
              _DayHeader(
                key: sameDay(day.date, page.today) ? _todayKey : null,
                day: day,
                isToday: sameDay(day.date, page.today),
              ),
              for (final item in day.items)
                switch (item) {
                  TxItem t => _TxTile(
                      tx: t,
                      busy: _busyId == t.id,
                      onTogglePaid: () => _togglePaid(t),
                      onTap: () => TransactionForm.open(context, existing: t),
                    ),
                  InvoiceItem i => _InvoiceTile(
                      invoice: i,
                      busy: _busyId == i.id,
                      onPay: () => _payInvoice(i),
                      onTap: i.card == null
                          ? null
                          : () => CardDetailScreen.open(context, cardId: i.card!.id, invoiceId: i.id),
                    ),
                },
              if (day.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    'Nenhum lançamento hoje',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onTapTitle,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTapTitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Mês anterior', onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
        Flexible(
          child: TextButton(
            onPressed: onTapTitle,
            child: Text(
              monthTitle(month),
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(tooltip: 'Próximo mês', onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.page});

  final TransactionsPage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget stat(String label, int value, Color? color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: muted),
              const SizedBox(height: 2),
              Text(money(value), style: theme.textTheme.titleSmall?.copyWith(color: color)),
            ],
          ),
        );

    Widget balance(String label, String hint, int value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: muted),
              const SizedBox(height: 2),
              Amount(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(hint, style: muted),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                stat('Receitas', page.income, colors.income),
                stat('Despesas', page.expense, colors.expense),
                stat('No cartão', page.cardExpense, null),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                balance('Realizado', 'só o que já foi pago', page.closing.realized),
                balance('Previsto', 'pagos + pendentes', page.closing.projected),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Saldo das contas no fim do mês', style: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({super.key, required this.day, required this.isToday});

  final DayGroup day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final value = theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);

    Widget line(String text, int cents) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: label),
            const SizedBox(width: 6),
            Amount(cents, style: value),
          ],
        );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: isToday ? scheme.primaryContainer : scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dayTitle(day.date), style: theme.textTheme.titleSmall),
                if (isToday)
                  Text('Hoje', style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              line('realizado', day.balance.realized),
              line('previsto', day.balance.projected),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: c);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 3)],
        Flexible(child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx, required this.busy, required this.onTogglePaid, this.onTap});

  final TxItem tx;
  final bool busy;
  final VoidCallback onTogglePaid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final scheme = theme.colorScheme;

    final amountColor = switch (tx.type) {
      TxType.income => colors.income,
      TxType.expense => colors.expense,
      TxType.transfer => scheme.onSurface,
    };
    final icon = tx.type == TxType.transfer ? Icons.swap_horiz : categoryIcon(tx.category?.icon);
    final iconColor = tx.type == TxType.transfer ? scheme.secondary : hexColor(tx.category?.color);

    final tags = <Widget>[
      if (tx.card != null)
        _Tag(
          tx.invoiceDueDate == null ? tx.card!.name : '${tx.card!.name} · fatura ${shortDate(tx.invoiceDueDate!)}',
          icon: Icons.credit_card,
        )
      else if (tx.type == TxType.transfer)
        _Tag('${tx.account?.name ?? '?'} → ${tx.toAccount?.name ?? '?'}', icon: Icons.account_balance_outlined)
      else if (tx.account != null)
        _Tag(tx.account!.name, icon: Icons.account_balance_outlined),
      if (tx.isFixed) const _Tag('Fixo', icon: Icons.repeat),
      if (tx.overdue) _Tag('Atrasado', icon: Icons.warning_amber_rounded, color: colors.warning),
    ];

    return InkWell(
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          IconBadge(icon: icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: tx.description),
                    if (tx.installmentNumber != null)
                      TextSpan(
                        text: '  ${tx.installmentNumber}/${tx.installmentTotal}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                  ]),
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(spacing: 10, runSpacing: 2, children: tags),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            money(tx.amount),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: tx.affectsBalance ? amountColor : amountColor.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(
            width: 44,
            child: !tx.affectsBalance
                ? Tooltip(
                    message: 'Entra no saldo pela fatura',
                    child: Icon(Icons.credit_card, size: 18, color: scheme.outline),
                  )
                : busy
                    ? const Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        tooltip: tx.paid ? 'Pago — marcar como pendente' : 'Pendente — marcar como pago',
                        onPressed: onTogglePaid,
                        icon: Icon(
                          tx.paid ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: tx.paid ? colors.income : (tx.overdue ? colors.warning : scheme.outline),
                        ),
                      ),
          ),
        ],
      ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.busy, required this.onPay, this.onTap});

  final InvoiceItem invoice;
  final bool busy;
  final VoidCallback onPay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final scheme = theme.colorScheme;
    final (statusText, statusColor) = switch (invoice.status) {
      InvoiceStatus.open => ('Aberta · fecha ${shortDate(invoice.closingDate)}', scheme.onSurfaceVariant),
      InvoiceStatus.closed => ('Fechada', scheme.onSurfaceVariant),
      InvoiceStatus.paid => ('Paga', colors.income),
      InvoiceStatus.overdue => ('Atrasada', colors.warning),
    };
    final shown = invoice.remaining > 0 ? invoice.remaining : invoice.total;

    return InkWell(
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          IconBadge(icon: Icons.credit_card, color: scheme.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoice.description, style: theme.textTheme.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Wrap(spacing: 10, runSpacing: 2, children: [
                  if (invoice.account != null) _Tag(invoice.account!.name, icon: Icons.account_balance_outlined),
                  _Tag(statusText, color: statusColor),
                  if (invoice.paidAmount > 0 && invoice.remaining > 0)
                    _Tag('pago ${money(invoice.paidAmount)} de ${money(invoice.total)}'),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            money(shown),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.expense,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(
            width: 44,
            child: busy
                ? const Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : invoice.status == InvoiceStatus.paid
                    ? Icon(Icons.check_circle, color: colors.income)
                    : IconButton(
                        tooltip: 'Pagar fatura',
                        onPressed: onPay,
                        icon: Icon(
                          Icons.radio_button_unchecked,
                          color: invoice.status == InvoiceStatus.overdue ? colors.warning : scheme.outline,
                        ),
                      ),
          ),
        ],
      ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.accounts, required this.selected, required this.includeCards});

  final List<Account> accounts;
  final Set<String> selected;
  final bool includeCards;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _selected = {...widget.selected};
  late bool _includeCards = widget.includeCards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text('Contas', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Os saldos consideram só as contas marcadas. Nenhuma marcada = todas.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final a in widget.accounts)
              CheckboxListTile(
                value: _selected.contains(a.id),
                onChanged: (v) => setState(() => v == true ? _selected.add(a.id) : _selected.remove(a.id)),
                title: Text(a.name),
                subtitle: Text('Saldo atual ${money(a.balance)}'),
                secondary: CircleAvatar(radius: 6, backgroundColor: hexColor(a.color) ?? theme.colorScheme.primary),
              ),
            const Divider(),
            SwitchListTile(
              value: _includeCards,
              onChanged: (v) => setState(() => _includeCards = v),
              title: const Text('Mostrar compras no cartão'),
              subtitle: const Text('Elas não mexem no saldo; a fatura sim'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _selected = {};
                      _includeCards = true;
                    }),
                    child: const Text('Limpar'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, (_selected, _includeCards)),
                    child: const Text('Aplicar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
