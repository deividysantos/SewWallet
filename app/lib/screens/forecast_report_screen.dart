import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/preferred_filter.dart';
import '../widgets/stitch.dart';
import 'transaction_form.dart';

/// Filtro de situação das previsões.
enum _StateFilter { all, open, closed, expired }

/// Previsões do mês: quanto foi previsto, abatido e quanto falta, separadas em fixas e avulsas.
class ForecastReportScreen extends StatefulWidget {
  const ForecastReportScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ForecastReportScreen()));

  @override
  State<ForecastReportScreen> createState() => _ForecastReportScreenState();
}

class _ForecastReportScreenState extends State<ForecastReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// null = a pagar e a receber.
  TxType? _type;
  _StateFilter _state = _StateFilter.all;

  /// Vazios = todas as contas e cartões.
  Set<String> _accountIds = {};
  Set<String> _cardIds = {};

  ForecastReport? _report;
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

  static const _reportKey = 'forecasts';

  Map<String, dynamic> _currentFilter() => {
    'type': _type?.name,
    'state': _state.name,
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
      _state = _StateFilter.values.where((s) => s.name == filterString(p, 'state')).firstOrNull ?? _StateFilter.all;
      _accountIds = filterIds(p, 'accountIds').where((id) => _catalog.account(id) != null).toSet();
      _cardIds = filterIds(p, 'cardIds').where((id) => _catalog.card(id) != null).toSet();
    }

    reload ? _set(change) : change();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.get(
        '/reports/forecasts',
        query: {
          'month': apiDate(_month),
          if (_type != null) 'type': _type == TxType.income ? 'INCOME' : 'EXPENSE',
          if (_state != _StateFilter.all) 'state': _state.name.toUpperCase(),
          if (_accountIds.isNotEmpty) 'accountIds': _accountIds.join(','),
          if (_cardIds.isNotEmpty) 'cardIds': _cardIds.join(','),
        },
      );
      if (mounted) setState(() => _report = ForecastReport.fromJson(data as Map<String, dynamic>));
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

  bool get _filtered => _type != null || _state != _StateFilter.all || _accountIds.isNotEmpty || _cardIds.isNotEmpty;

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
                      ButtonSegment(value: TxType.expense, label: Text('A pagar')),
                      ButtonSegment(value: TxType.income, label: Text('A receber')),
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
                        (_StateFilter.all, 'Todas'),
                        (_StateFilter.open, 'Abertas'),
                        (_StateFilter.closed, 'Encerradas'),
                        (_StateFilter.expired, 'Expiradas'),
                      ])
                        ChoiceChip(label: Text(t), selected: _state == v, onSelected: (_) => change(() => _state = v)),
                    ],
                  ),
                  label('Contas e cartões (nenhum marcado = todos)'),
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
                          _state = _StateFilter.all;
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

  Future<void> _setState(TxItem f, String state) async {
    setState(() => _busyId = f.id);
    try {
      await context.read<Session>().api.patch('/transactions/${f.id}/forecast-state', {'state': state});
      await _catalog.refresh();
      if (mounted) showSnack(context, state == 'CLOSED' ? 'Previsão encerrada' : 'Previsão reaberta');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _openEntry(ForecastEntry e) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _EntrySheet(
        entry: e,
        onRealize: () {
          Navigator.pop(ctx);
          TransactionForm.open(context, abate: e.tx);
        },
        onEdit: () {
          Navigator.pop(ctx);
          TransactionForm.open(context, existing: e.tx);
        },
        onEditAbatement: (t) {
          Navigator.pop(ctx);
          TransactionForm.open(context, existing: t);
        },
        onSetState: (s) {
          Navigator.pop(ctx);
          _setState(e.tx, s);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Previsões'),
        actions: [
          PreferredFilterButton(report: _reportKey, current: _currentFilter, apply: _applyFilter),
          IconButton(
            tooltip: 'Filtros',
            onPressed: _openFilters,
            icon: Badge(isLabelVisible: _filtered, child: const Icon(Icons.tune)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TransactionForm.open(context, forecast: true),
        icon: const Icon(Icons.add),
        label: const Text('Nova previsão'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
            Row(
              children: [
                IconButton(
                  tooltip: 'Mês anterior',
                  onPressed: () => _set(() => _month = DateTime(_month.year, _month.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => _set(() => _month = DateTime(DateTime.now().year, DateTime.now().month)),
                    child: Text(
                      monthTitle(_month),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Próximo mês',
                  onPressed: () => _set(() => _month = DateTime(_month.year, _month.month + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
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

  List<Widget> _content(ForecastReport report) {
    if (report.items.isEmpty) {
      return [
        const EmptyView(
          icon: Icons.insights_outlined,
          message:
              'Nenhuma previsão neste mês.\nPrevisões são valores que você acha que vai gastar ou receber, '
              'como R\$ 200 de gasolina. Os lançamentos reais vão abatendo delas.',
        ),
      ];
    }
    final fixed = report.items.where((e) => e.fixed).toList();
    final single = report.items.where((e) => !e.fixed).toList();
    return [
      _Summary(report: report, type: _type),
      if (fixed.isNotEmpty) ...[
        _SectionTitle('Fixas', '${fixed.length}', icon: Icons.repeat),
        for (final e in fixed) _EntryTile(entry: e, busy: _busyId == e.tx.id, onTap: () => _openEntry(e)),
      ],
      if (single.isNotEmpty) ...[
        _SectionTitle('Avulsas deste mês', '${single.length}', icon: Icons.event_outlined),
        for (final e in single) _EntryTile(entry: e, busy: _busyId == e.tx.id, onTap: () => _openEntry(e)),
      ],
    ];
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.report, required this.type});

  final ForecastReport report;
  final TxType? type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final caps = muted?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w600);

    Widget block(String title, ForecastTotals t, Color color) {
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(color: color)),
          const SizedBox(height: 6),
          Row(
            children: [
              stat('Previsto', t.planned),
              stat('Abatido', t.abated),
              stat('Resta', t.remaining, c: color),
            ],
          ),
          const SizedBox(height: 4),
          Text('Contando nos saldos agora: ${money(t.effective)}', style: muted),
        ],
      );
    }

    final showExpense = type != TxType.income && (report.expense.count > 0 || type == TxType.expense);
    final showIncome = type != TxType.expense && (report.income.count > 0 || type == TxType.income);
    return StitchedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showExpense) block('A pagar', report.expense, colors.expense),
          if (showExpense && showIncome) ...[const SizedBox(height: 12), const Stitch(), const SizedBox(height: 12)],
          if (showIncome) block('A receber', report.income, colors.income),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.count, {required this.icon});
  final String title;
  final String count;
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
          Text(count, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

String _stateText(ForecastState s) => switch (s) {
  ForecastState.open => 'Aberta',
  ForecastState.closed => 'Encerrada',
  ForecastState.expired => 'Expirada',
};

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.busy, required this.onTap});

  final ForecastEntry entry;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final scheme = theme.colorScheme;
    final tx = entry.tx;
    final f = entry.info;
    final color = tx.type == TxType.income ? colors.income : colors.expense;
    final progress = f.planned <= 0 ? 0.0 : (f.abated / f.planned).clamp(0.0, 1.0);
    final faded = !f.isOpen;
    final where = tx.card?.name ?? tx.account?.name ?? '';

    return Opacity(
      opacity: faded ? 0.6 : 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              IconBadge(icon: categoryIcon(tx.category?.icon), color: hexColor(tx.category?.color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.description,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'até ${shortDate(tx.date)} · $where · ${_stateText(f.state)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: f.state == ForecastState.expired ? colors.warning : scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.15),
                      ),
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
                          money(f.remaining),
                          style: SewFonts.mono(
                            theme.textTheme.bodyMedium,
                          ).copyWith(color: color, fontWeight: FontWeight.w600),
                        ),
                        Text('de ${money(f.planned)}', style: theme.textTheme.labelSmall),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntrySheet extends StatelessWidget {
  const _EntrySheet({
    required this.entry,
    required this.onRealize,
    required this.onEdit,
    required this.onEditAbatement,
    required this.onSetState,
  });

  final ForecastEntry entry;
  final VoidCallback onRealize;
  final VoidCallback onEdit;
  final ValueChanged<TxItem> onEditAbatement;
  final ValueChanged<String> onSetState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = entry.tx;
    final f = entry.info;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tx.description, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${tx.type == TxType.income ? 'A receber' : 'A pagar'} até ${shortDate(tx.date)}/${tx.date.year} · '
              '${_stateText(f.state)}${entry.fixed ? ' · Fixa' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text('Previsto ${money(f.planned)} · abatido ${money(f.abated)} · resta ${money(f.remaining)}'),
            const SizedBox(height: 16),
            Text('Lançamentos que abateram', style: theme.textTheme.titleSmall),
            if (entry.abatements.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Nenhum ainda.', style: theme.textTheme.bodySmall),
              ),
            for (final a in entry.abatements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(a.paid || a.card != null ? Icons.check_circle_outline : Icons.radio_button_unchecked),
                title: Text(a.description),
                subtitle: Text('${shortDate(a.date)} · ${a.card?.name ?? a.account?.name ?? ''}'),
                trailing: Text(money(a.amount), style: SewFonts.mono(theme.textTheme.bodyMedium)),
                onTap: () => onEditAbatement(a),
              ),
            const SizedBox(height: 16),
            if (f.isOpen) ...[
              FilledButton.icon(
                onPressed: onRealize,
                icon: const Icon(Icons.add),
                label: const Text('Lançar valor real'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => onSetState('CLOSED'), child: const Text('Encerrar previsão')),
            ] else
              OutlinedButton(onPressed: () => onSetState('OPEN'), child: const Text('Reabrir previsão')),
            const SizedBox(height: 8),
            TextButton(onPressed: onEdit, child: const Text('Editar previsão')),
          ],
        ),
      ),
    );
  }
}
