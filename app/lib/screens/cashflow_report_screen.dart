import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../state/settings.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/preferred_filter.dart';
import '../widgets/stitch.dart';

enum _Gran { day, week, month }

/// Fluxo de caixa por dia, semana ou mês; acumulado (com saldo anterior) ou só do período.
///
/// O intervalo exibido anda com as setas (‹ ›), como na tela de lançamentos:
/// visão por dia = 1 mês, por semana = 13 semanas, por mês = 12 meses.
/// Um intervalo personalizado fica dentro dos filtros.
class CashflowReportScreen extends StatefulWidget {
  const CashflowReportScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CashflowReportScreen()));

  @override
  State<CashflowReportScreen> createState() => _CashflowReportScreenState();
}

class _CashflowReportScreenState extends State<CashflowReportScreen> {
  _Gran _gran = _Gran.month;
  bool _cumulative = true;
  bool _projected = true;

  /// Considerar previsões abertas (pelo valor que falta abater).
  late bool _forecasts = context.read<AppSettings>().includeForecasts;

  /// Quantos intervalos para trás (<0) ou para frente (>0) do padrão.
  int _offset = 0;

  /// Intervalo escolhido à mão (as setas o deslocam pelo seu próprio tamanho).
  DateTimeRange? _custom;

  /// Vazio = todas as contas.
  Set<String> _accountIds = {};

  bool _filtersExpanded = false;

  CashflowReport? _report;
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
    final saved = _catalog.preferred(_reportKey);
    if (saved != null) _applyFilter(saved, reload: false);
    _load();
  }

  static const _reportKey = 'cashflow';

  Map<String, dynamic> _currentFilter() => {
    'gran': _gran.name,
    'cumulative': _cumulative,
    'projected': _projected,
    'forecasts': _forecasts,
    'accountIds': _accountIds.toList(),
  };

  void _applyFilter(Map<String, dynamic> p, {bool reload = true}) {
    void change() {
      _gran = _Gran.values.where((g) => g.name == filterString(p, 'gran')).firstOrNull ?? _Gran.month;
      _cumulative = filterBool(p, 'cumulative') ?? true;
      _projected = filterBool(p, 'projected') ?? true;
      _forecasts = filterBool(p, 'forecasts') ?? _forecasts;
      _accountIds = filterIds(p, 'accountIds').where((id) => _catalog.account(id) != null).toSet();
      _offset = 0;
      _custom = null;
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

  // ---------- intervalo ----------

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Segunda-feira da semana de [d].
  static DateTime _startOfWeek(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// Mês de calendário exibido nas visões por dia e por semana (como na tela inicial).
  DateTime get _month {
    final t = _today();
    return DateTime(t.year, t.month + _offset);
  }

  /// Ano de calendário exibido na visão por mês.
  int get _year => _today().year + _offset;

  /// Quantos meses inteiros o período específico cobre (null se não começa no dia 1 e
  /// termina no último dia de um mês). Assim as setas andam por mês, sem errar a
  /// quantidade de dias de cada um.
  static int? _wholeMonths(DateTimeRange r) {
    final endsAtMonthEnd = DateTime(r.end.year, r.end.month + 1, 0).day == r.end.day;
    if (r.start.day != 1 || !endsAtMonthEnd) return null;
    return (r.end.year - r.start.year) * 12 + r.end.month - r.start.month + 1;
  }

  DateTimeRange get _window {
    final custom = _custom;
    if (custom != null) {
      final months = _wholeMonths(custom);
      if (months != null) {
        final start = DateTime(custom.start.year, custom.start.month + months * _offset, 1);
        return DateTimeRange(start: start, end: DateTime(start.year, start.month + months, 0));
      }
      final shift = (custom.end.difference(custom.start).inDays + 1) * _offset;
      return DateTimeRange(
        start: DateTime(custom.start.year, custom.start.month, custom.start.day + shift),
        end: DateTime(custom.end.year, custom.end.month, custom.end.day + shift),
      );
    }
    switch (_gran) {
      case _Gran.day:
        final m = _month;
        return DateTimeRange(start: m, end: DateTime(m.year, m.month + 1, 0));
      case _Gran.week:
        // Semanas (seg–dom) que tocam o mês.
        final m = _month;
        final last = DateTime(m.year, m.month + 1, 0);
        final start = _startOfWeek(m);
        final lastMonday = _startOfWeek(last);
        return DateTimeRange(start: start, end: DateTime(lastMonday.year, lastMonday.month, lastMonday.day + 6));
      case _Gran.month:
        return DateTimeRange(start: DateTime(_year, 1, 1), end: DateTime(_year, 12, 31));
    }
  }

  bool get _isDefaultWindow => _custom == null && _offset == 0;

  String get _windowTitle {
    final custom = _custom;
    if (custom == null) {
      return switch (_gran) {
        _Gran.day || _Gran.week => monthTitle(_month),
        _Gran.month => '$_year',
      };
    }
    final w = _window;
    String yy(DateTime d) => '${d.year % 100}'.padLeft(2, '0');
    final months = _wholeMonths(w);
    if (months == 1) return monthTitle(w.start);
    if (months != null) {
      String mon(DateTime d) {
        final s = DateFormat('MMM', 'pt_BR').format(d).replaceAll('.', '');
        return '${s[0].toUpperCase()}${s.substring(1)}/${yy(d)}';
      }

      return '${mon(w.start)} – ${mon(w.end)}';
    }
    return '${shortDate(w.start)}/${yy(w.start)} – ${shortDate(w.end)}/${yy(w.end)}';
  }

  String get _stepName {
    final custom = _custom;
    if (custom != null) {
      final months = _wholeMonths(custom);
      if (months == 1) return 'mês';
      return months != null ? '$months meses' : 'intervalo';
    }
    return switch (_gran) {
      _Gran.day || _Gran.week => 'mês',
      _Gran.month => 'ano',
    };
  }

  void _move(int delta) => _set(() => _offset += delta);

  void _resetWindow() => _set(() {
    _offset = 0;
    _custom = null;
  });

  // ---------- dados ----------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final w = _window;
    try {
      final data = await context.read<Session>().api.get(
        '/reports/cashflow',
        query: {
          'granularity': _gran.name,
          'mode': _cumulative ? 'cumulative' : 'period',
          'basis': _projected ? 'projected' : 'realized',
          'from': apiDate(w.start),
          'to': apiDate(w.end),
          if (_accountIds.isNotEmpty) 'accountIds': _accountIds.join(','),
          'forecasts': '$_forecasts',
        },
      );
      if (mounted) setState(() => _report = CashflowReport.fromJson(data as Map<String, dynamic>));
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

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _window,
      helpText: 'Período do relatório',
    );
    if (picked == null) return;
    _set(() {
      _custom = picked;
      _offset = 0;
    });
  }

  Future<void> _pickAccounts() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AccountsSheet(accounts: _catalog.accounts, selected: _accountIds),
    );
    if (picked == null) return;
    _set(() => _accountIds = picked);
  }

  String get _accountsLabel {
    if (_accountIds.isEmpty) return 'Todas as contas';
    if (_accountIds.length == 1) return _catalog.account(_accountIds.first)?.name ?? '1 conta';
    return '${_accountIds.length} contas';
  }

  String get _granLabel => switch (_gran) {
    _Gran.day => 'Por dia',
    _Gran.week => 'Por semana',
    _Gran.month => 'Por mês',
  };

  /// Todos os filtros em um modal (rolável, para telas pequenas).
  Future<void> _openFiltersModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filtros', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                _filtersPanel(
                  onChanged: (change) {
                    _set(change);
                    setSheet(() {});
                  },
                  refresh: () => setSheet(() {}),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Fechar')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Painel com todos os filtros. [onChanged] aplica a mudança (e recarrega);
  /// [refresh] redesenha quem mostra o painel (o modal) depois de escolher contas/período.
  Widget _filtersPanel({required void Function(VoidCallback) onChanged, VoidCallback? refresh}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_Gran>(
          segments: const [
            ButtonSegment(value: _Gran.day, label: Text('Dia')),
            ButtonSegment(value: _Gran.week, label: Text('Semana')),
            ButtonSegment(value: _Gran.month, label: Text('Mês')),
          ],
          selected: {_gran},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onChanged(() {
            _gran = s.first;
            // cada visão tem um intervalo padrão
            _offset = 0;
            _custom = null;
          }),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Acumulado')),
            ButtonSegment(value: false, label: Text('Só o período')),
          ],
          selected: {_cumulative},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onChanged(() => _cumulative = s.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Previsto')),
            ButtonSegment(value: false, label: Text('Realizado')),
          ],
          selected: {_projected},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onChanged(() => _projected = s.first),
        ),
        CheckboxListTile(
          key: const ValueKey('cashflowForecasts'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _forecasts,
          onChanged: _projected ? (v) => onChanged(() => _forecasts = v ?? true) : null,
          title: const Text('Considerar previsões'),
          subtitle: Text(
            _projected ? 'Previsões abertas entram pelo valor que falta abater' : 'O realizado nunca inclui previsões',
          ),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            await _pickAccounts();
            refresh?.call();
          },
          icon: Badge(
            isLabelVisible: _accountIds.isNotEmpty,
            child: const Icon(Icons.account_balance_outlined, size: 18),
          ),
          label: Text(_accountsLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _pickRange();
                  refresh?.call();
                },
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(
                  _custom == null ? 'Escolher período específico' : 'Período: $_windowTitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (!_isDefaultWindow)
              TextButton(
                onPressed: () => onChanged(() {
                  _offset = 0;
                  _custom = null;
                }),
                child: const Text('Padrão'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _cumulative
              ? 'Começa com o saldo das contas acumulado até o início do período.'
              : 'Começa do zero: mostra só o que entra e sai dentro do período.',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          _projected
              ? 'Inclui pendentes (atrasados contam como se fossem pagos hoje). Cartões entram pela fatura, no vencimento.'
              : 'Só o que já foi pago ou recebido.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Linha compacta: resumo dos filtros + expandir / abrir em modal.
  Widget _filtersBar() {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium;

    Widget chip(String text, {IconData? icon, bool highlight = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: scheme.onSurfaceVariant), const SizedBox(width: 4)],
          Text(text, style: labelStyle),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      chip(_granLabel),
                      const SizedBox(width: 6),
                      chip(_cumulative ? 'Acumulado' : 'Só o período'),
                      const SizedBox(width: 6),
                      chip(_projected ? 'Previsto' : 'Realizado'),
                      if (_projected) ...[
                        const SizedBox(width: 6),
                        chip(_forecasts ? 'Com previsões' : 'Sem previsões', icon: Icons.insights_outlined),
                      ],
                      const SizedBox(width: 6),
                      chip(_accountsLabel, icon: Icons.account_balance_outlined, highlight: _accountIds.isNotEmpty),
                      if (_custom != null) ...[
                        const SizedBox(width: 6),
                        chip('Período específico', icon: Icons.date_range_outlined, highlight: true),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _filtersExpanded ? 'Recolher filtros' : 'Mostrar filtros',
            onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
            icon: Icon(_filtersExpanded ? Icons.expand_less : Icons.expand_more),
          ),
          IconButton(tooltip: 'Todos os filtros', onPressed: _openFiltersModal, icon: const Icon(Icons.tune)),
        ],
      ),
    );
  }

  Widget _periodSwitcher() {
    return Row(
      children: [
        IconButton(tooltip: 'Anterior ($_stepName)', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: TextButton(
            onPressed: _resetWindow, // volta ao período atual
            child: Text(
              _windowTitle,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(tooltip: 'Próximo ($_stepName)', onPressed: () => _move(1), icon: const Icon(Icons.chevron_right)),
      ],
    );
  }

  String _bucketLabel(CashflowBucket b) => switch (_gran) {
    _Gran.day => dayTitle(b.start),
    _Gran.week => '${shortDate(b.start)} – ${shortDate(b.end)}',
    _Gran.month => () {
      // Um ano só: "Janeiro". Vários anos (período específico): "Jan/26".
      final w = _window;
      final s = w.start.year == w.end.year
          ? DateFormat('MMMM', 'pt_BR').format(b.start)
          : DateFormat('MMM/yy', 'pt_BR').format(b.start).replaceAll('.', '');
      return s[0].toUpperCase() + s.substring(1);
    }(),
  };

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluxo de caixa'),
        actions: [PreferredFilterButton(report: _reportKey, current: _currentFilter, apply: _applyFilter)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
            _periodSwitcher(),
            _filtersBar(),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _filtersExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: _filtersPanel(onChanged: _set),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (_error != null && report == null)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: ErrorView(message: _error!, onRetry: _load),
              )
            else if (report != null) ...[
              _Totals(report: report),
              if (report.buckets.length > 1) _BalanceChart(report: report, labelOf: _bucketLabel),
              _BucketTable(report: report, labelOf: _bucketLabel),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountsSheet extends StatefulWidget {
  const _AccountsSheet({required this.accounts, required this.selected});

  final List<Account> accounts;
  final Set<String> selected;

  @override
  State<_AccountsSheet> createState() => _AccountsSheetState();
}

class _AccountsSheetState extends State<_AccountsSheet> {
  late Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text('Contas no relatório', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Nenhuma marcada = todas. Transferências entre contas marcadas não contam como entrada/saída; '
              'para uma conta fora da seleção, contam.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final a in widget.accounts)
                  CheckboxListTile(
                    value: _selected.contains(a.id),
                    onChanged: (v) => setState(() => v == true ? _selected.add(a.id) : _selected.remove(a.id)),
                    title: Text(a.archived ? '${a.name} (arquivada)' : a.name),
                    secondary: CircleAvatar(radius: 6, backgroundColor: hexColor(a.color) ?? theme.colorScheme.primary),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                TextButton(onPressed: () => setState(() => _selected = {}), child: const Text('Todas')),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('Aplicar')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.report});

  final CashflowReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget stat(String label, int value, {Color? color}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: muted),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Amount(
                value,
                color: color,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );

    final hasTransfers = report.transfersIn != 0 || report.transfersOut != 0;
    return StitchedCard(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Row(
              children: [
                stat('Entradas', report.income, color: colors.income),
                stat('Saídas', report.expense, color: colors.expense),
                stat('Resultado', report.net),
              ],
            ),
            if (hasTransfers) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  stat('Transf. recebidas', report.transfersIn),
                  stat('Transf. enviadas', report.transfersOut),
                  const Spacer(),
                ],
              ),
            ],
            const Divider(height: 24),
            Row(
              children: [
                stat('Saldo inicial', report.openingBalance),
                stat('Saldo final', report.closingBalance),
                const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceChart extends StatelessWidget {
  const _BalanceChart({required this.report, required this.labelOf});

  final CashflowReport report;
  final String Function(CashflowBucket) labelOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final buckets = report.buckets;
    final values = [for (final b in buckets) b.closing / 100];
    final minY = min(0.0, values.reduce(min));
    final maxY = max(0.0, values.reduce(max));
    final pad = (maxY - minY).abs() * 0.1 + 1;
    final compact = NumberFormat.compactCurrency(locale: 'pt_BR', symbol: r'R$');
    final step = max(1, (buckets.length / 5).ceil());
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text('Saldo no fim de cada período', style: theme.textTheme.titleSmall),
          ),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (minY < 0) HorizontalLine(y: 0, color: scheme.outline, strokeWidth: 1, dashArray: [4, 4]),
                  ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (v, meta) => (v == meta.min || v == meta.max)
                          ? const SizedBox.shrink()
                          : Text(compact.format(v), style: labelStyle),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) {
                        final i = v.round();
                        if (i != v || i < 0 || i >= buckets.length || i % step != 0) return const SizedBox.shrink();
                        final label = labelOf(buckets[i]);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(label.split(' – ').first.split(',').last.trim(), style: labelStyle),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => scheme.inverseSurface,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${labelOf(buckets[s.x.round()])}\n${money(buckets[s.x.round()].closing)}',
                          TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
                    color: FinanceColors.of(context).accent,
                    barWidth: 2.5,
                    dotData: FlDotData(show: buckets.length <= 16),
                    belowBarData: BarAreaData(
                      show: true,
                      color: FinanceColors.of(context).accent.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BucketTable extends StatelessWidget {
  const _BucketTable({required this.report, required this.labelOf});

  final CashflowReport report;
  final String Function(CashflowBucket) labelOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = FinanceColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final head = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final cell = SewFonts.mono(theme.textTheme.bodySmall);

    Widget row(List<Widget> cells, {Color? bg}) => Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 4, child: cells[0]),
          for (final c in cells.skip(1))
            Expanded(
              flex: 5,
              child: Align(alignment: Alignment.centerRight, child: c),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        row([
          Text('Período', style: head),
          Text('Entradas', style: head),
          Text('Saídas', style: head),
          Text('Saldo final', style: head),
        ]),
        const Divider(height: 1),
        for (final b in report.buckets)
          row([
            Text(labelOf(b), style: theme.textTheme.bodySmall, maxLines: 2),
            Text(money(b.income), style: cell.copyWith(color: b.income == 0 ? scheme.outline : colors.income)),
            Text(money(b.expense), style: cell.copyWith(color: b.expense == 0 ? scheme.outline : colors.expense)),
            Amount(b.closing, style: cell.copyWith(fontWeight: FontWeight.w600)),
          ], bg: !today.isBefore(b.start) && !today.isAfter(b.end) ? colors.accent.withValues(alpha: 0.1) : null),
      ],
    );
  }
}
