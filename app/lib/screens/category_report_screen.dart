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
import '../widgets/stitch.dart';
import 'transaction_form.dart';

/// Cores para categorias sem cor definida (tons da paleta Ateliê).
const _fallbackColors = [
  Color(0xFF2E6A6E),
  Color(0xFFB8612A),
  Color(0xFF6B5B95),
  Color(0xFF3A7449),
  Color(0xFFA8740F),
  Color(0xFF8C4A5A),
  Color(0xFF4F6D8F),
];

/// Quantas categorias aparecem com cor própria no gráfico; o resto vira "Outras".
const _chartSlices = 6;

Color _colorOf(CategorySpend c, int index, BuildContext context) {
  if (c.id == null) return Theme.of(context).colorScheme.outline;
  return hexColor(c.color) ?? _fallbackColors[index % _fallbackColors.length];
}

String _monthShort(DateTime d) {
  final s = DateFormat('MMM', 'pt_BR').format(d).replaceAll('.', '');
  return s[0].toUpperCase() + s.substring(1);
}

/// Intervalo exibido: mês ou ano de calendário (andando com ‹ ›) ou período específico.
class _Period {
  _Period({required this.yearView, required this.offset, this.custom});

  final bool yearView;
  final int offset;
  final DateTimeRange? custom;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static int? wholeMonths(DateTimeRange r) {
    final endsAtMonthEnd = DateTime(r.end.year, r.end.month + 1, 0).day == r.end.day;
    if (r.start.day != 1 || !endsAtMonthEnd) return null;
    return (r.end.year - r.start.year) * 12 + r.end.month - r.start.month + 1;
  }

  DateTimeRange get window {
    final c = custom;
    if (c != null) {
      final months = wholeMonths(c);
      if (months != null) {
        final start = DateTime(c.start.year, c.start.month + months * offset, 1);
        return DateTimeRange(start: start, end: DateTime(start.year, start.month + months, 0));
      }
      final shift = (c.end.difference(c.start).inDays + 1) * offset;
      return DateTimeRange(
        start: DateTime(c.start.year, c.start.month, c.start.day + shift),
        end: DateTime(c.end.year, c.end.month, c.end.day + shift),
      );
    }
    final t = _today;
    if (yearView) {
      final y = t.year + offset;
      return DateTimeRange(start: DateTime(y, 1, 1), end: DateTime(y, 12, 31));
    }
    final m = DateTime(t.year, t.month + offset);
    return DateTimeRange(start: m, end: DateTime(m.year, m.month + 1, 0));
  }

  /// "Novembro 2026", "2026", "Jan/26 – Mar/26" ou "10/11/26 – 16/11/26".
  String get title => _label(window);

  /// Rótulo do período anterior (para a comparação): "outubro", "2025", "período anterior".
  String get previousLabel {
    if (custom != null) return 'o período anterior';
    final w = window;
    if (yearView) return '${w.start.year - 1}';
    final p = DateTime(w.start.year, w.start.month - 1);
    return DateFormat('MMMM', 'pt_BR').format(p);
  }

  /// "em novembro", "em 2026", "no período".
  String get inLabel {
    if (custom != null) return 'no período';
    final w = window;
    return yearView ? 'em ${w.start.year}' : 'em ${DateFormat('MMMM', 'pt_BR').format(w.start)}';
  }

  /// "Média 3 meses" / "Média 3 anos" / "Média 3 períodos".
  String get averageLabel => custom != null ? 'Média 3 períodos' : (yearView ? 'Média 3 anos' : 'Média 3 meses');

  String get stepName {
    final c = custom;
    if (c != null) {
      final months = wholeMonths(c);
      if (months == 1) return 'mês';
      return months != null ? '$months meses' : 'intervalo';
    }
    return yearView ? 'ano' : 'mês';
  }

  static String _label(DateTimeRange w) {
    String yy(DateTime d) => '${d.year % 100}'.padLeft(2, '0');
    final months = wholeMonths(w);
    if (months == 1) return monthTitle(w.start);
    if (months == 12 && w.start.month == 1) return '${w.start.year}';
    if (months != null) return '${_monthShort(w.start)}/${yy(w.start)} – ${_monthShort(w.end)}/${yy(w.end)}';
    return '${shortDate(w.start)}/${yy(w.start)} – ${shortDate(w.end)}/${yy(w.end)}';
  }
}

/// Opções do relatório (as mesmas valem para o detalhe de uma categoria).
class _Options {
  _Options({required this.income, required this.realized, required this.byPayment});
  final bool income;
  final bool realized;
  final bool byPayment;

  Map<String, String> query(DateTimeRange w) => {
        'kind': income ? 'INCOME' : 'EXPENSE',
        'basis': realized ? 'realized' : 'projected',
        'cardDate': byPayment ? 'payment' : 'purchase',
        'from': apiDate(w.start),
        'to': apiDate(w.end),
      };
}

/// Quanto foi gasto (ou recebido) por categoria, com comparação e média.
class CategoryReportScreen extends StatefulWidget {
  const CategoryReportScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoryReportScreen()));

  @override
  State<CategoryReportScreen> createState() => _CategoryReportScreenState();
}

class _CategoryReportScreenState extends State<CategoryReportScreen> {
  bool _income = false;
  bool _realized = false;
  late bool _byPayment = context.read<AppSettings>().cardDateView == CardDateView.payment;
  bool _yearView = false;
  int _offset = 0;
  DateTimeRange? _custom;

  CategoryReport? _report;
  bool _loading = true;
  String? _error;
  int? _touched;

  late final Catalog _catalog;
  int _seenRevision = -1;

  _Period get _period => _Period(yearView: _yearView, offset: _offset, custom: _custom);
  _Options get _options => _Options(income: _income, realized: _realized, byPayment: _byPayment);

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
      final data = await context.read<Session>().api.get('/reports/categories', query: _options.query(_period.window));
      if (mounted) {
        setState(() {
          _report = CategoryReport.fromJson(data as Map<String, dynamic>);
          _touched = null;
        });
      }
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
      initialDateRange: _period.window,
      helpText: 'Período do relatório',
    );
    if (picked == null) return;
    _set(() {
      _custom = picked;
      _offset = 0;
    });
  }

  Future<void> _openOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void change(VoidCallback fn) {
            _set(fn);
            setSheet(() {});
          }

          final theme = Theme.of(ctx);
          Widget label(String text) => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Text(text, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              );

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Opções do relatório', style: theme.textTheme.titleMedium),
                  label('Navegar por'),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Mês')),
                      ButtonSegment(value: true, label: Text('Ano')),
                    ],
                    selected: {_yearView},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => change(() {
                      _yearView = s.first;
                      _offset = 0;
                      _custom = null;
                    }),
                  ),
                  label('Considerar'),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Previsto')),
                      ButtonSegment(value: true, label: Text('Realizado')),
                    ],
                    selected: {_realized},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => change(() => _realized = s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _realized
                          ? 'Só o que já foi pago; no cartão, compras até hoje.'
                          : 'Inclui pendentes e lançamentos futuros do período (fixos, parcelas).',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  label('Compras no cartão pela'),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Data da compra')),
                      ButtonSegment(value: true, label: Text('Data do pagamento')),
                    ],
                    selected: {_byPayment},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => change(() => _byPayment = s.first),
                  ),
                  label('Período'),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await _pickRange();
                            setSheet(() {});
                          },
                          icon: const Icon(Icons.date_range_outlined, size: 18),
                          label: Text(
                            _custom == null ? 'Escolher período específico' : 'Período: ${_period.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (_custom != null || _offset != 0)
                        TextButton(
                          onPressed: () => change(() {
                            _custom = null;
                            _offset = 0;
                          }),
                          child: const Text('Padrão'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Fechar')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openCategory(CategorySpend c, int index) {
    _CategoryDetailScreen.open(
      context,
      category: c,
      color: _colorOf(c, index, context),
      period: _period,
      options: _options,
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final period = _period;
    final customized = _realized || _byPayment != (context.read<AppSettings>().cardDateView == CardDateView.payment);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Por categoria'),
        actions: [
          IconButton(
            tooltip: 'Opções do relatório',
            onPressed: _openOptions,
            icon: Badge(isLabelVisible: customized || _custom != null || _yearView, child: const Icon(Icons.tune)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
            Row(
              children: [
                IconButton(
                  tooltip: 'Anterior (${period.stepName})',
                  onPressed: () => _set(() => _offset--),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => _set(() {
                      _offset = 0;
                      _custom = null;
                    }),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(period.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Próximo (${period.stepName})',
                  onPressed: () => _set(() => _offset++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Despesas'), icon: Icon(Icons.south_east, size: 16)),
                  ButtonSegment(value: true, label: Text('Receitas'), icon: Icon(Icons.north_east, size: 16)),
                ],
                selected: {_income},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _set(() => _income = s.first),
              ),
            ),
            if (_error != null && report == null)
              Padding(padding: const EdgeInsets.only(top: 48), child: ErrorView(message: _error!, onRetry: _load))
            else if (report != null) ..._content(report, period),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(CategoryReport report, _Period period) {
    final theme = Theme.of(context);
    final rows = report.categories.where((c) => c.total != 0 || c.previous != 0).toList();
    final withValue = rows.where((c) => c.total > 0).toList();

    if (withValue.isEmpty) {
      return [
        _Summary(report: report, period: period, income: _income),
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _income ? 'Nenhuma receita ${period.inLabel}.' : 'Nenhum gasto ${period.inLabel}. Bom sinal.',
            textAlign: TextAlign.center,
            style: SewFonts.display(TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ),
        ),
      ];
    }

    final uncategorized = rows.where((c) => c.id == null).firstOrNull;
    final indexOf = {for (var i = 0; i < rows.length; i++) rows[i]: i};

    return [
      _Summary(report: report, period: period, income: _income),
      _Donut(
        categories: withValue,
        total: report.total,
        colorOf: (c) => _colorOf(c, indexOf[c]!, context),
        touched: _touched,
        onTouch: (i) => setState(() => _touched = i),
      ),
      if (uncategorized != null && uncategorized.share >= 0.15)
        _UncategorizedHint(
          share: uncategorized.share,
          onTap: () => _openCategory(uncategorized, indexOf[uncategorized]!),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            Expanded(child: Text('Categorias', style: theme.textTheme.titleSmall)),
            Text(
              'vs ${period.previousLabel}',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      for (final c in rows)
        _CategoryRow(
          category: c,
          color: _colorOf(c, indexOf[c]!, context),
          income: _income,
          highlighted: _touched != null && _touched! < withValue.length && withValue[_touched!] == c,
          onTap: () => _openCategory(c, indexOf[c]!),
        ),
      if (report.history.any((h) => h.total != 0)) ...[
        const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 0), child: Stitch()),
        _HistoryBars(
          title: _income ? 'Receitas nos últimos 6 meses' : 'Gastos nos últimos 6 meses',
          history: report.history,
          color: FinanceColors.of(context).accent,
        ),
      ],
    ];
  }
}

/// Resumo: total do período, comparação com o anterior e média.
class _Summary extends StatelessWidget {
  const _Summary({required this.report, required this.period, required this.income});

  final CategoryReport report;
  final _Period period;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final caps = muted?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w600);
    final days = report.to.difference(report.from).inDays + 1;

    return StitchedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((income ? 'Recebido ${period.inLabel}' : 'Gasto ${period.inLabel}').toUpperCase(), style: caps),
          const SizedBox(height: 2),
          HeroAmount(report.total, fontSize: 30, color: theme.colorScheme.onSurface),
          const SizedBox(height: 6),
          _Delta(current: report.total, previous: report.previousTotal, income: income, versus: period.previousLabel),
          const SizedBox(height: 12),
          const Stitch(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _MiniStat(label: period.averageLabel, value: money(report.averageTotal))),
              Expanded(child: _MiniStat(label: 'Por dia', value: money(report.total ~/ max(1, days)))),
              Expanded(child: _MiniStat(label: 'Lançamentos', value: '${report.count}')),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: SewFonts.mono(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// "▲ 12% vs outubro (R$ 300 a mais)". Em despesas, subir é ruim; em receitas, bom.
class _Delta extends StatelessWidget {
  const _Delta({required this.current, required this.previous, required this.income, required this.versus, this.compact = false});

  final int current;
  final int previous;
  final bool income;
  final String versus;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final style = (compact ? theme.textTheme.labelSmall : theme.textTheme.bodySmall) ?? const TextStyle();
    final diff = current - previous;

    if (previous == 0 && current == 0) return const SizedBox.shrink();
    if (previous == 0) {
      return Text(compact ? 'novo' : 'Nada em $versus', style: style.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }
    if (diff == 0) {
      return Text(compact ? 'igual' : 'Igual a $versus', style: style.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }

    final up = diff > 0;
    final good = income ? up : !up;
    final color = good ? colors.income : colors.expense;
    final pct = (diff.abs() / previous * 100).round();
    final text = compact
        ? '${up ? '▲' : '▼'} $pct%'
        : '${up ? '▲' : '▼'} $pct% vs $versus (${money(diff.abs())} a ${up ? 'mais' : 'menos'})';
    return Text(text, style: style.copyWith(color: color, fontWeight: FontWeight.w600));
  }
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.categories,
    required this.total,
    required this.colorOf,
    required this.touched,
    required this.onTouch,
  });

  final List<CategorySpend> categories;
  final int total;
  final Color Function(CategorySpend) colorOf;
  final int? touched;
  final ValueChanged<int?> onTouch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = categories.take(_chartSlices).toList();
    final rest = categories.skip(_chartSlices).fold<int>(0, (s, c) => s + c.total);

    final slices = <(String, int, Color)>[
      for (final c in top) (c.name, c.total, colorOf(c)),
      if (rest > 0) ('Outras', rest, scheme.outlineVariant),
    ];
    final focus = touched != null && touched! < slices.length ? slices[touched!] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 2,
                centerSpaceRadius: 68,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    // Um toque escolhe a fatia; tocar de novo (ou fora) limpa.
                    if (event is! FlTapUpEvent) return;
                    final i = response?.touchedSection?.touchedSectionIndex;
                    onTouch(i == null || i < 0 || i == touched ? null : i);
                  },
                ),
                sections: [
                  for (var i = 0; i < slices.length; i++)
                    PieChartSectionData(
                      value: slices[i].$2.toDouble(),
                      color: slices[i].$3,
                      radius: touched == i ? 38 : 30,
                      showTitle: false,
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    focus?.$1 ?? '${categories.length} categorias',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (focus != null) ...[
                    FittedBox(child: Text(money(focus.$2), style: SewFonts.mono(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w700))),
                    Text('${(focus.$2 / max(1, total) * 100).round()}%',
                        style: SewFonts.display(TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: scheme.onSurface))),
                  ] else
                    Text('toque numa fatia',
                        style: SewFonts.display(TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UncategorizedHint extends StatelessWidget {
  const _UncategorizedHint({required this.share, required this.onTap});

  final double share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.label_off_outlined, color: colors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${(share * 100).round()}% está sem categoria. Categorizar deixa este relatório mais fiel.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.color,
    required this.income,
    required this.highlighted,
    required this.onTap,
  });

  final CategorySpend category;
  final Color color;
  final bool income;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = category;
    final muted = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: highlighted ? color.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            IconBadge(icon: c.id == null ? Icons.label_off_outlined : categoryIcon(c.icon), color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(c.name, style: theme.textTheme.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(money(c.total), style: SewFonts.mono(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: c.share.clamp(0.0, 1.0),
                      minHeight: 5,
                      color: color,
                      backgroundColor: scheme.surfaceContainerHigh,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            '${(c.share * 100).toStringAsFixed(c.share < 0.1 ? 1 : 0)}%',
                            '${c.count} ${c.count == 1 ? 'lançamento' : 'lançamentos'}',
                            if (c.average > 0) 'média ${money(c.average)}',
                          ].join(' · '),
                          style: muted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Delta(current: c.total, previous: c.previous, income: income, versus: '', compact: true),
                    ],
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

/// Barras mês a mês; o último mês (o do período) em destaque.
class _HistoryBars extends StatelessWidget {
  const _HistoryBars({required this.title, required this.history, required this.color});

  final String title;
  final List<MonthTotal> history;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxY = history.map((h) => h.total).fold<int>(0, max).toDouble();
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final compact = NumberFormat.compactCurrency(locale: 'pt_BR', symbol: r'R$');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                maxY: maxY <= 0 ? 1 : maxY * 1.15,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => scheme.inverseSurface,
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      '${monthTitle(history[group.x].month)}\n${money(history[group.x].total)}',
                      TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 18,
                      getTitlesWidget: (v, meta) {
                        final h = history[v.toInt()];
                        return h.total == 0 ? const SizedBox.shrink() : Text(compact.format(h.total / 100), style: labelStyle);
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, meta) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_monthShort(history[v.toInt()].month), style: labelStyle),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < history.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: max(0, history[i].total).toDouble(),
                        width: 22,
                        color: i == history.length - 1 ? color : color.withValues(alpha: 0.35),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uma categoria: histórico de 6 meses e os lançamentos do período.
class _CategoryDetailScreen extends StatefulWidget {
  const _CategoryDetailScreen({
    required this.category,
    required this.color,
    required this.period,
    required this.options,
  });

  final CategorySpend category;
  final Color color;
  final _Period period;
  final _Options options;

  static Future<void> open(
    BuildContext context, {
    required CategorySpend category,
    required Color color,
    required _Period period,
    required _Options options,
  }) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _CategoryDetailScreen(category: category, color: color, period: period, options: options),
      ));

  @override
  State<_CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<_CategoryDetailScreen> {
  CategoryDetail? _detail;
  String? _error;
  bool _loading = true;
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
      final data = await context.read<Session>().api.get('/reports/categories/detail', query: {
        ...widget.options.query(widget.period.window),
        'categoryId': widget.category.id ?? 'none',
      });
      if (mounted) setState(() => _detail = CategoryDetail.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.category;
    final detail = _detail;
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
            StitchedCard(
              child: Row(
                children: [
                  IconBadge(icon: c.id == null ? Icons.label_off_outlined : categoryIcon(c.icon), color: widget.color, radius: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.period.title.toUpperCase(), style: muted?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w600)),
                        HeroAmount(detail?.total ?? c.total, fontSize: 26),
                        _Delta(
                          current: c.total,
                          previous: c.previous,
                          income: widget.options.income,
                          versus: widget.period.previousLabel,
                        ),
                        if (c.average > 0)
                          Text('Média dos 3 anteriores: ${money(c.average)}', style: muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null && detail == null)
              Padding(padding: const EdgeInsets.only(top: 32), child: ErrorView(message: _error!, onRetry: _load))
            else if (detail != null) ...[
              if (detail.history.any((h) => h.total != 0))
                _HistoryBars(title: 'Últimos 6 meses', history: detail.history, color: widget.color),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '${detail.items.length} ${detail.items.length == 1 ? 'lançamento' : 'lançamentos'}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (detail.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Nada nesta categoria no período.', textAlign: TextAlign.center, style: muted),
                ),
              for (final e in detail.items) _EntryTile(entry: e, income: widget.options.income),
            ],
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.income});

  final CategoryEntry entry;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final scheme = theme.colorScheme;
    final tx = entry.tx;
    final refund = entry.amount < 0;
    final where = tx.card?.name ?? tx.account?.name;
    final details = [
      dayTitle(entry.date),
      ?where,
      if (tx.installmentNumber != null) '${tx.installmentNumber}/${tx.installmentTotal}',
      if (refund) 'estorno',
      if (!tx.paid && tx.card == null) 'pendente',
    ].join(' · ');

    return InkWell(
      onTap: () => TransactionForm.open(context, existing: tx),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(tx.card != null ? Icons.credit_card : Icons.account_balance_outlined, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.description, style: theme.textTheme.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(details, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${refund ? '− ' : ''}${money(entry.amount.abs())}',
              style: SewFonts.mono(theme.textTheme.bodyMedium).copyWith(
                fontWeight: FontWeight.w600,
                color: refund ? colors.income : (income ? colors.income : colors.expense),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
