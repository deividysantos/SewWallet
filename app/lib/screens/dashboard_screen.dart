import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../state/settings.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/month_switcher.dart';
import '../widgets/new_transaction_fab.dart';
import '../widgets/preferred_filter.dart';
import '../widgets/stitch.dart';
import 'card_detail_screen.dart';
import 'category_report_screen.dart';
import 'counterpart_report_screen.dart';
import 'forecast_report_screen.dart';
import 'settings_screen.dart';
import 'suggestions_screen.dart';

/// Aba Início: painel do mês (‹ › troca o mês). Filtros: contas, previsões e contrapartidas;
/// o filtro preferido (★) abre sozinho.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _reportKey = 'dashboard';

  DateTime _month = MonthSwitcher.current();
  Set<String> _accountIds = {};
  late bool _forecasts = context.read<AppSettings>().includeForecasts;
  bool _counterparts = true;

  /// O preferido só é aplicado uma vez (ao abrir), e não por cima de algo que o usuário já mexeu.
  bool _preferredHandled = false;

  Dashboard? _data;

  /// Sugestões de lançamento (notificações dos bancos) esperando decisão.
  int _suggestions = 0;
  bool _loading = true;
  String? _error;

  late final Catalog _catalog;
  int _seenRevision = -1;

  @override
  void initState() {
    super.initState();
    _catalog = context.read<Catalog>();
    _seenRevision = _catalog.revision;
    _catalog.addListener(_onCatalog);
    _takePreferred();
    _load();
  }

  void _takePreferred() {
    if (_preferredHandled || !_catalog.loaded) return;
    _preferredHandled = true;
    final saved = _catalog.preferred(_reportKey);
    if (saved != null) _applyFilter(saved, reload: false);
  }

  void _onCatalog() {
    if (_catalog.revision == _seenRevision) return;
    _seenRevision = _catalog.revision;
    _takePreferred();
    _load();
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalog);
    super.dispose();
  }

  Map<String, dynamic> _currentFilter() => {
    'accountIds': _accountIds.toList(),
    'forecasts': _forecasts,
    'counterparts': _counterparts,
  };

  void _applyFilter(Map<String, dynamic> p, {bool reload = true}) {
    void change() {
      _accountIds = filterIds(p, 'accountIds').where((id) => _catalog.account(id) != null).toSet();
      _forecasts = filterBool(p, 'forecasts') ?? _forecasts;
      _counterparts = filterBool(p, 'counterparts') ?? true;
    }

    reload ? _set(change) : setState(change);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.get(
        '/reports/dashboard',
        query: {
          'month': apiDate(_month),
          if (_accountIds.isNotEmpty) 'accountIds': _accountIds.join(','),
          'forecasts': '$_forecasts',
          'counterparts': '$_counterparts',
        },
      );
      if (mounted) setState(() => _data = Dashboard.fromJson(data as Map<String, dynamic>));
      _loadSuggestionCount();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Não atrapalha o painel se falhar (servidor antigo, por exemplo).
  Future<void> _loadSuggestionCount() async {
    try {
      final j = await context.read<Session>().api.get('/suggestions/count');
      if (mounted) setState(() => _suggestions = (j as Map)['pending'] as int? ?? 0);
    } catch (_) {}
  }

  Future<void> _openSuggestions() async {
    await SuggestionsScreen.open(context);
    _loadSuggestionCount();
  }

  void _set(VoidCallback change) {
    _preferredHandled = true;
    setState(change);
    _load();
  }

  Future<void> _pickAccounts() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        var selected = {..._accountIds};
        return StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Contas no painel (nenhuma = todas)', style: Theme.of(ctx).textTheme.titleMedium),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final a in _catalog.accounts)
                        CheckboxListTile(
                          value: selected.contains(a.id),
                          onChanged: (v) => setSheet(() => v == true ? selected.add(a.id) : selected.remove(a.id)),
                          title: Text(a.archived ? '${a.name} (arquivada)' : a.name),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      TextButton(onPressed: () => setSheet(() => selected = {}), child: const Text('Todas')),
                      const Spacer(),
                      FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Aplicar')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) _set(() => _accountIds = picked);
  }

  String get _accountsLabel {
    if (_accountIds.isEmpty) return 'Todas as contas';
    if (_accountIds.length == 1) return _catalog.account(_accountIds.first)?.name ?? '1 conta';
    return '${_accountIds.length} contas';
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Início'),
        actions: [
          IconButton(
            key: const ValueKey('suggestionsButton'),
            tooltip: 'Sugestões',
            onPressed: _openSuggestions,
            icon: Badge(
              isLabelVisible: _suggestions > 0,
              label: Text('$_suggestions'),
              child: const Icon(Icons.auto_awesome_outlined),
            ),
          ),
          PreferredFilterButton(report: _reportKey, current: _currentFilter, apply: _applyFilter),
          IconButton(
            tooltip: 'Configurações',
            onPressed: () => SettingsScreen.open(context),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: const NewTransactionFab(),
      body: RefreshIndicator(
        onRefresh: () => _catalog.refresh(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
            MonthSwitcher(month: _month, onChanged: (m) => _set(() => _month = m)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Wrap: em tela estreita os filtros quebram a linha em vez de sumir pela lateral.
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.account_balance_outlined, size: 18),
                    label: Text(_accountsLabel),
                    onPressed: _pickAccounts,
                  ),
                  FilterChip(
                    key: const ValueKey('dashForecasts'),
                    label: const Text('Previsões'),
                    selected: _forecasts,
                    onSelected: (v) => _set(() => _forecasts = v),
                  ),
                  FilterChip(
                    key: const ValueKey('dashCounterparts'),
                    label: const Text('Contrapartidas'),
                    selected: _counterparts,
                    onSelected: (v) => _set(() => _counterparts = v),
                  ),
                ],
              ),
            ),
            if (_error != null && data == null)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: ErrorView(message: _error!, onRetry: _load),
              )
            else if (data != null)
              ..._content(data),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(Dashboard d) => [
    if (_suggestions > 0)
      Card(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: Text(_suggestions == 1 ? '1 sugestão de lançamento' : '$_suggestions sugestões de lançamento'),
          subtitle: const Text('Lidas nas notificações dos bancos'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openSuggestions,
        ),
      ),
    _BalanceCard(data: d),
    _ResultCard(data: d, counterparts: _counterparts),
    if (d.invoices.isNotEmpty || d.cards.isNotEmpty) _CardsCard(data: d, forecasts: _forecasts),
    if (d.topExpenses.isNotEmpty) _TopCategories(data: d),
    _ExtrasCard(data: d),
  ];
}

TextStyle? _caps(BuildContext context) => Theme.of(context).textTheme.labelSmall?.copyWith(
  color: Theme.of(context).colorScheme.onSurfaceVariant,
  letterSpacing: 1.1,
  fontWeight: FontWeight.w600,
);

Widget _stat(BuildContext context, String label, int value, {Color? color, String? sub, bool big = false}) {
  return Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _statColumn(context, label, value, color: color, sub: sub, big: big),
    ),
  );
}

Widget _statColumn(BuildContext context, String label, int value, {Color? color, String? sub, bool big = false}) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(label.toUpperCase(), style: _caps(context), maxLines: 1),
      ),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Amount(
          value,
          color: color,
          style: (big ? theme.textTheme.titleLarge : theme.textTheme.bodyLarge)?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      if (sub != null)
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(sub, style: theme.textTheme.labelSmall, maxLines: 1),
        ),
    ],
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {required this.icon, this.onMore});
  final String title;
  final IconData icon;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
          if (onMore != null)
            InkWell(
              onTap: onMore,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    Text('Ver', style: theme.textTheme.labelMedium),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.data});
  final Dashboard data;

  @override
  Widget build(BuildContext context) {
    final current = data.isCurrentMonth;
    final past = data.to.isBefore(data.today);
    return StitchedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle('Saldo das contas', icon: Icons.account_balance_wallet_outlined),
          Row(
            children: [
              if (current)
                _stat(context, 'Hoje', data.todayBalance.realized, big: true)
              else
                _stat(context, 'Início do mês', past ? data.opening.realized : data.opening.projected, big: true),
              _stat(
                context,
                past ? 'Fim do mês' : 'Fim do mês (previsto)',
                past ? data.monthEnd.realized : data.monthEnd.projected,
                big: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.data, required this.counterparts});
  final Dashboard data;
  final bool counterparts;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final theme = Theme.of(context);
    String realized(int v) => 'realizado ${money(v)}';
    return StitchedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle('Resultado do mês', icon: Icons.balance_outlined),
          Row(
            children: [
              _stat(
                context,
                'Receitas',
                data.income.projected,
                color: colors.income,
                sub: realized(data.income.realized),
              ),
              _stat(
                context,
                'Despesas',
                data.expense.projected,
                color: colors.expense,
                sub: realized(data.expense.realized),
              ),
              _stat(context, 'Resultado', data.net.projected, sub: realized(data.net.realized)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Compras no cartão contam na data da compra.${counterparts ? '' : ' Sem os pares de contrapartida.'}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CardsCard extends StatelessWidget {
  const _CardsCard({required this.data, required this.forecasts});
  final Dashboard data;
  final bool forecasts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final scheme = theme.colorScheme;
    final toPay = data.invoices.fold<int>(0, (s, i) => s + i.remaining);
    return StitchedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle('Faturas e cartões', icon: Icons.credit_card),
          if (data.invoices.isNotEmpty) ...[
            for (final i in data.invoices)
              InkWell(
                onTap: () => CardDetailScreen.open(context, cardId: i.cardId, invoiceId: i.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Fatura ${i.cardName}', style: theme.textTheme.bodyMedium),
                            Text(
                              'vence ${shortDate(i.dueDate)} · ${switch (i.status) {
                                InvoiceStatus.open => 'aberta',
                                InvoiceStatus.closed => 'fechada',
                                InvoiceStatus.paid => 'paga',
                                InvoiceStatus.overdue => 'atrasada',
                              }}${forecasts && i.forecastTotal > 0 ? ' · + ${money(i.forecastTotal)} previsto' : ''}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: i.status == InvoiceStatus.overdue ? colors.warning : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Amount(
                            i.remaining > 0 ? i.remaining : i.total,
                            color: i.remaining > 0 ? colors.expense : null,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (i.remaining > 0 && i.paid > 0)
                            Text('de ${money(i.total)}', style: theme.textTheme.labelSmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (data.invoices.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: Text('A pagar no mês: ${money(toPay)}', style: theme.textTheme.labelMedium),
              ),
          ],
          if (data.cards.any((c) => c.limit != null && c.limit! > 0)) ...[
            const SizedBox(height: 8),
            const Stitch(),
            const SizedBox(height: 8),
            for (final c in data.cards.where((c) => c.limit != null && c.limit! > 0))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Limite ${c.name}', style: theme.textTheme.labelMedium)),
                        Text('${money(c.limitUsed)} de ${money(c.limit!)}', style: theme.textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (c.limitUsed / c.limit!).clamp(0.0, 1.0),
                        minHeight: 6,
                        color: hexColor(c.color) ?? colors.accent,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TopCategories extends StatelessWidget {
  const _TopCategories({required this.data});
  final Dashboard data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = data.expense.projected;
    return StitchedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle('Maiores gastos', icon: Icons.donut_large, onMore: () => CategoryReportScreen.open(context)),
          for (final c in data.topExpenses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  IconBadge(icon: categoryIcon(c.icon), color: hexColor(c.color), radius: 15),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(c.name, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                            ),
                            Amount(c.total, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: total <= 0 ? 0 : (c.total / total).clamp(0.0, 1.0),
                            minHeight: 4,
                            color: hexColor(c.color) ?? scheme.primary,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExtrasCard extends StatelessWidget {
  const _ExtrasCard({required this.data});
  final Dashboard data;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final theme = Theme.of(context);
    final f = data;
    final hasForecasts = f.forecastExpense.count > 0 || f.forecastIncome.count > 0;
    final hasCounterparts = f.counterpartIncome.count > 0 || f.counterpartExpense.count > 0;
    return Column(
      children: [
        StitchedCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CardTitle('Previsões', icon: Icons.insights_outlined, onMore: () => ForecastReportScreen.open(context)),
              if (!hasForecasts)
                Text('Nenhuma previsão neste mês.', style: theme.textTheme.bodySmall)
              else
                Row(
                  children: [
                    _stat(
                      context,
                      'Falta pagar',
                      f.forecastExpense.remaining,
                      color: colors.expense,
                      sub: 'de ${money(f.forecastExpense.planned)}',
                    ),
                    _stat(
                      context,
                      'Falta receber',
                      f.forecastIncome.remaining,
                      color: colors.income,
                      sub: 'de ${money(f.forecastIncome.planned)}',
                    ),
                  ],
                ),
            ],
          ),
        ),
        StitchedCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CardTitle(
                'Contrapartidas',
                icon: Icons.compare_arrows,
                onMore: () => CounterpartReportScreen.open(context),
              ),
              if (!hasCounterparts)
                Text('Nenhuma contrapartida neste mês.', style: theme.textTheme.bodySmall)
              else
                Row(
                  children: [
                    _stat(
                      context,
                      'A receber de volta',
                      f.counterpartIncome.pending,
                      color: colors.income,
                      sub: 'recebido ${money(f.counterpartIncome.settled)}',
                    ),
                    _stat(
                      context,
                      'A devolver',
                      f.counterpartExpense.pending,
                      color: colors.expense,
                      sub: 'pago ${money(f.counterpartExpense.settled)}',
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
