import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/month_switcher.dart';
import '../widgets/preferred_filter.dart';
import '../widgets/stitch.dart';
import 'transaction_form.dart';

enum _Status { all, pending, paid }

/// Contrapartidas do mês (pela data da contrapartida): quanto falta receber de volta e quanto já
/// voltou, cada uma com o lançamento de origem.
class CounterpartReportScreen extends StatefulWidget {
  const CounterpartReportScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CounterpartReportScreen()));

  @override
  State<CounterpartReportScreen> createState() => _CounterpartReportScreenState();
}

class _CounterpartReportScreenState extends State<CounterpartReportScreen> {
  static const _reportKey = 'counterparts';

  DateTime _month = MonthSwitcher.current();

  /// null = a receber de volta e a devolver.
  TxType? _type;
  _Status _status = _Status.all;
  Set<String> _accountIds = {};
  Set<String> _cardIds = {};

  CounterpartReport? _report;
  bool _loading = true;
  String? _error;
  String? _busyId;

  late final Catalog _catalog;
  int _seenRevision = -1;

  @override
  void initState() {
    super.initState();
    _catalog = context.read<Catalog>();
    _seenRevision = _catalog.revision;
    _catalog.addListener(_onCatalog);
    final saved = _catalog.preferred(_reportKey);
    if (saved != null) _applyFilter(saved, reload: false);
    _load();
  }

  void _onCatalog() {
    if (_catalog.revision == _seenRevision) return;
    _seenRevision = _catalog.revision;
    _load();
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalog);
    super.dispose();
  }

  Map<String, dynamic> _currentFilter() => {
    'type': _type?.name,
    'status': _status.name,
    'accountIds': _accountIds.toList(),
    'cardIds': _cardIds.toList(),
  };

  void _applyFilter(Map<String, dynamic> p, {bool reload = true}) {
    void change() {
      final t = filterString(p, 'type');
      _type = t == 'income'
          ? TxType.income
          : t == 'expense'
          ? TxType.expense
          : null;
      _status = _Status.values.where((s) => s.name == filterString(p, 'status')).firstOrNull ?? _Status.all;
      _accountIds = filterIds(p, 'accountIds').where((id) => _catalog.account(id) != null).toSet();
      _cardIds = filterIds(p, 'cardIds').where((id) => _catalog.card(id) != null).toSet();
    }

    reload ? _set(change) : change();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.get(
        '/reports/counterparts',
        query: {
          'month': apiDate(_month),
          if (_type != null) 'type': _type == TxType.income ? 'INCOME' : 'EXPENSE',
          if (_status != _Status.all) 'status': _status == _Status.paid ? 'PAID' : 'PENDING',
          if (_accountIds.isNotEmpty) 'accountIds': _accountIds.join(','),
          if (_cardIds.isNotEmpty) 'cardIds': _cardIds.join(','),
        },
      );
      if (mounted) setState(() => _report = CounterpartReport.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _set(VoidCallback change) {
    setState(change);
    _load();
  }

  bool get _filtered => _type != null || _status != _Status.all || _accountIds.isNotEmpty || _cardIds.isNotEmpty;

  Future<void> _togglePaid(CounterpartEntry e) async {
    setState(() => _busyId = e.tx.id);
    try {
      await context.read<Session>().api.patch('/transactions/${e.tx.id}/status', {
        'status': e.tx.paid ? 'PENDING' : 'PAID',
      });
      await _catalog.refresh();
      if (mounted) {
        showSnack(
          context,
          e.tx.paid ? 'Voltou para pendente' : (e.toReceive ? 'Marcada como recebida' : 'Marcada como paga'),
        );
      }
    } catch (err) {
      if (mounted) showSnack(context, err.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void change(VoidCallback c) {
            _set(c);
            setSheet(() {});
          }

          final theme = Theme.of(ctx);
          Widget label(String t) => Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(t, style: theme.textTheme.bodySmall),
          );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Filtros', style: theme.textTheme.titleMedium),
                  label('Tipo'),
                  SegmentedButton<TxType?>(
                    segments: const [
                      ButtonSegment(value: null, label: Text('Todas')),
                      ButtonSegment(value: TxType.income, label: Text('A receber')),
                      ButtonSegment(value: TxType.expense, label: Text('A devolver')),
                    ],
                    selected: {_type},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => change(() => _type = s.first),
                  ),
                  label('Situação'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (v, t) in const [
                        (_Status.all, 'Todas'),
                        (_Status.pending, 'Pendentes'),
                        (_Status.paid, 'Quitadas'),
                      ])
                        ChoiceChip(
                          label: Text(t),
                          selected: _status == v,
                          onSelected: (_) => change(() => _status = v),
                        ),
                    ],
                  ),
                  label('Conta da contrapartida / cartão da compra (nenhum marcado = todos)'),
                  for (final a in _catalog.accounts)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _accountIds.contains(a.id),
                      onChanged: (v) => change(() => v == true ? _accountIds.add(a.id) : _accountIds.remove(a.id)),
                      secondary: const Icon(Icons.account_balance_outlined),
                      title: Text(a.name),
                    ),
                  for (final c in _catalog.cards)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _cardIds.contains(c.id),
                      onChanged: (v) => change(() => v == true ? _cardIds.add(c.id) : _cardIds.remove(c.id)),
                      secondary: const Icon(Icons.credit_card),
                      title: Text(c.name),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => change(() {
                          _type = null;
                          _status = _Status.all;
                          _accountIds = {};
                          _cardIds = {};
                        }),
                        child: const Text('Limpar'),
                      ),
                      const Spacer(),
                      FilledButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Fechar')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openEntry(CounterpartEntry e) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final o = e.origin;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(o.description, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Origem: ${money(o.amount)} em ${shortDate(o.date)}/${o.date.year} · ${o.card?.name ?? o.account?.name ?? ''}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '${e.toReceive ? 'Volta' : 'Sai'} ${money(e.tx.amount)} em ${shortDate(e.tx.date)}/${e.tx.date.year} · '
                  '${e.tx.account?.name ?? ''} · ${e.tx.paid ? (e.toReceive ? 'recebida' : 'paga') : 'pendente'}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _togglePaid(e);
                  },
                  icon: Icon(e.tx.paid ? Icons.undo : Icons.check),
                  label: Text(
                    e.tx.paid
                        ? 'Voltar para pendente'
                        : e.toReceive
                        ? 'Marcar como recebida'
                        : 'Marcar como paga',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    TransactionForm.open(context, existing: o);
                  },
                  child: const Text('Editar lançamento de origem'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    TransactionForm.open(context, existing: e.tx);
                  },
                  child: const Text('Editar contrapartida'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrapartidas'),
        actions: [
          PreferredFilterButton(report: _reportKey, current: _currentFilter, apply: _applyFilter),
          IconButton(
            tooltip: 'Filtros',
            onPressed: _openFilters,
            icon: Badge(isLabelVisible: _filtered, child: const Icon(Icons.tune)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
            MonthSwitcher(month: _month, onChanged: (m) => _set(() => _month = m)),
            if (_error != null && report == null)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: ErrorView(message: _error!, onRetry: _load),
              )
            else if (report != null)
              ..._content(report),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(CounterpartReport report) {
    if (report.items.isEmpty && report.income.count == 0 && report.expense.count == 0) {
      return const [
        EmptyView(
          icon: Icons.compare_arrows,
          message:
              'Nenhuma contrapartida neste mês.\nAo lançar uma compra para alguém que vai te pagar depois, '
              'ligue "Gerar contrapartida" no lançamento.',
        ),
      ];
    }
    final pending = report.items.where((e) => !e.tx.paid).toList();
    final paid = report.items.where((e) => e.tx.paid).toList();
    return [
      _Summary(report: report, type: _type),
      if (pending.isNotEmpty) ...[
        _SectionTitle('Pendentes', pending.length, icon: Icons.schedule),
        for (final e in pending) _EntryTile(entry: e, busy: _busyId == e.tx.id, onTap: () => _openEntry(e)),
      ],
      if (paid.isNotEmpty) ...[
        _SectionTitle('Quitadas', paid.length, icon: Icons.check_circle_outline),
        for (final e in paid) _EntryTile(entry: e, busy: _busyId == e.tx.id, onTap: () => _openEntry(e)),
      ],
    ];
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.report, required this.type});
  final CounterpartReport report;
  final TxType? type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final caps = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w600,
    );

    Widget block(String title, CounterpartTotals t, Color color, String pendingLabel, String settledLabel) {
      Widget stat(String label, int v, {Color? c}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: caps),
            const SizedBox(height: 2),
            Amount(
              v,
              color: c,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
      final progress = t.total <= 0 ? 0.0 : t.settled / t.total;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(color: color)),
          const SizedBox(height: 6),
          Row(
            children: [
              stat(pendingLabel, t.pending, c: color),
              stat(settledLabel, t.settled),
              stat('Total', t.total),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      );
    }

    final showIncome = type != TxType.expense && (report.income.count > 0 || type == TxType.income);
    final showExpense = type != TxType.income && (report.expense.count > 0 || type == TxType.expense);
    return StitchedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showIncome) block('A receber de volta', report.income, colors.income, 'Falta receber', 'Recebido'),
          if (showIncome && showExpense) ...[const SizedBox(height: 12), const Stitch(), const SizedBox(height: 12)],
          if (showExpense) block('A devolver', report.expense, colors.expense, 'Falta pagar', 'Pago'),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.count, {required this.icon});
  final String title;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(width: 6),
          Text('$count', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.busy, required this.onTap});
  final CounterpartEntry entry;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final o = entry.origin;
    final cp = entry.tx;
    final color = entry.toReceive ? colors.income : colors.expense;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            IconBadge(icon: o.card != null ? Icons.credit_card : Icons.compare_arrows, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.description, style: theme.textTheme.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${o.card?.name ?? o.account?.name ?? ''} em ${shortDate(o.date)} → '
                    '${cp.account?.name ?? ''} em ${shortDate(cp.date)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        money(cp.amount),
                        style: SewFonts.mono(
                          theme.textTheme.bodyMedium,
                        ).copyWith(color: color, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        cp.paid ? (entry.toReceive ? 'recebida' : 'paga') : 'pendente',
                        style: theme.textTheme.labelSmall?.copyWith(color: cp.overdue ? colors.warning : null),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
