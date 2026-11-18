import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

enum _Gran { day, week, month }

/// Fluxo de caixa por dia, semana ou mês; acumulado (com saldo anterior) ou só do período.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Gran _gran = _Gran.month;
  bool _cumulative = true;
  bool _projected = true;
  DateTimeRange? _range;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.get('/reports/cashflow', query: {
        'granularity': _gran.name,
        'mode': _cumulative ? 'cumulative' : 'period',
        'basis': _projected ? 'projected' : 'realized',
        if (_range != null) 'from': apiDate(_range!.start),
        if (_range != null) 'to': apiDate(_range!.end),
      });
      if (mounted) setState(() => _report = CashflowReport.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final r = _report;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _range ?? (r == null ? null : DateTimeRange(start: r.from, end: r.to)),
      helpText: 'Período do relatório',
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  void _set(VoidCallback change) {
    setState(change);
    _load();
  }

  String _bucketLabel(CashflowBucket b) => switch (_gran) {
        _Gran.day => dayTitle(b.start),
        _Gran.week => '${shortDate(b.start)} – ${shortDate(b.end)}',
        _Gran.month => () {
            final s = DateFormat('MMM/yy', 'pt_BR').format(b.start).replaceAll('.', '');
            return s[0].toUpperCase() + s.substring(1);
          }(),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report;

    return Scaffold(
      appBar: AppBar(title: const Text('Fluxo de caixa')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
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
                    onSelectionChanged: (s) => _set(() {
                      _gran = s.first;
                      _range = null; // cada visão tem uma janela padrão
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
                    onSelectionChanged: (s) => _set(() => _cumulative = s.first),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Previsto')),
                      ButtonSegment(value: false, label: Text('Realizado')),
                    ],
                    selected: {_projected},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _set(() => _projected = s.first),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickRange,
                          icon: const Icon(Icons.date_range_outlined, size: 18),
                          label: Text(report == null
                              ? 'Período'
                              : '${shortDate(report.from)}/${report.from.year % 100} a ${shortDate(report.to)}/${report.to.year % 100}'),
                        ),
                      ),
                      if (_range != null)
                        TextButton(onPressed: () => _set(() => _range = null), child: const Text('Padrão')),
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
              ),
            ),
            if (_error != null && report == null)
              Padding(padding: const EdgeInsets.only(top: 48), child: ErrorView(message: _error!, onRetry: _load))
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

class _Totals extends StatelessWidget {
  const _Totals({required this.report});

  final CashflowReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget stat(String label, int value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: muted),
            Amount(value, color: color, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ]),
        );

    final hasTransfers = report.transfersIn != 0 || report.transfersOut != 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              stat('Entradas', report.income, color: colors.income),
              stat('Saídas', report.expense, color: colors.expense),
              stat('Resultado', report.net),
            ]),
            if (hasTransfers) ...[
              const SizedBox(height: 8),
              Row(children: [
                stat('Transf. recebidas', report.transfersIn),
                stat('Transf. enviadas', report.transfersOut),
                const Spacer(),
              ]),
            ],
            const Divider(height: 24),
            Row(children: [
              stat('Saldo inicial', report.openingBalance),
              stat('Saldo final', report.closingBalance),
              const Spacer(),
            ]),
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
                  getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(horizontalLines: [
                  if (minY < 0) HorizontalLine(y: 0, color: scheme.outline, strokeWidth: 1, dashArray: [4, 4]),
                ]),
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
                    color: scheme.primary,
                    barWidth: 2.5,
                    dotData: FlDotData(show: buckets.length <= 16),
                    belowBarData: BarAreaData(show: true, color: scheme.primary.withValues(alpha: 0.12)),
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
    final cell = theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    Widget row(List<Widget> cells, {Color? bg}) => Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(flex: 4, child: cells[0]),
            for (final c in cells.skip(1)) Expanded(flex: 5, child: Align(alignment: Alignment.centerRight, child: c)),
          ]),
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
          row(
            [
              Text(labelOf(b), style: cell, maxLines: 2),
              Text(money(b.income), style: cell?.copyWith(color: b.income == 0 ? scheme.outline : colors.income)),
              Text(money(b.expense), style: cell?.copyWith(color: b.expense == 0 ? scheme.outline : colors.expense)),
              Amount(b.closing, style: cell?.copyWith(fontWeight: FontWeight.w600)),
            ],
            bg: !today.isBefore(b.start) && !today.isAfter(b.end) ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
          ),
      ],
    );
  }
}
