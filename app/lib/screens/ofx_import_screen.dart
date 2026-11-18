import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Escolhe um arquivo .ofx e abre a revisão da importação para a fatura que fecha em [refMonth].
/// Retorna true se algo foi importado.
Future<bool> pickAndImportOfx(BuildContext context, {required String cardId, required DateTime refMonth}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['ofx', 'OFX'],
    withData: true,
  );
  final bytes = picked?.files.single.bytes;
  if (bytes == null || !context.mounted) return false;
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => OfxImportScreen(cardId: cardId, refMonth: refMonth, ofx: decodeOfx(bytes)),
    ),
  );
  return result == true;
}

/// OFX 1.x costuma vir em Windows-1252 (o cabeçalho diz); latin1 cobre os acentos.
String decodeOfx(List<int> bytes) {
  final head = latin1.decode(bytes.take(400).toList(), allowInvalid: true).toUpperCase();
  if (head.contains('UTF-8') || head.contains('ENCODING="UTF-8"')) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  return latin1.decode(bytes, allowInvalid: true);
}

class _Entry {
  _Entry(Map<String, dynamic> j)
      : index = j['index'] as int,
        memo = j['memo'] as String,
        name = j['name'] as String,
        date = parseDate(j['date'] as String),
        amount = j['amount'] as int,
        isCredit = j['type'] == 'INCOME',
        status = j['status'] as String,
        installmentNumber = (j['installment'] as Map?)?['number'] as int?,
        installmentTotal = (j['installment'] as Map?)?['total'] as int?,
        creates = j['creates'] as int,
        matchDescription = (j['match'] as Map?)?['description'] as String?,
        matchReason = (j['match'] as Map?)?['reason'] as String?,
        description = TextEditingController(text: j['name'] as String),
        categoryId = j['suggestedCategoryId'] as String?;

  final int index;
  final String memo;
  final String name;
  final DateTime date;
  final int amount;
  final bool isCredit;

  /// new | matched | ignored
  final String status;
  final int? installmentNumber;
  final int? installmentTotal;
  final int creates;
  final String? matchDescription;
  final String? matchReason;

  final TextEditingController description;
  String? categoryId;
  bool include = true;

  String? get installmentLabel => installmentNumber == null ? null : 'Parcela $installmentNumber/$installmentTotal';
}

/// Revisão da importação: lançamentos novos (nome e categoria editáveis), já lançados e ignorados.
class OfxImportScreen extends StatefulWidget {
  const OfxImportScreen({super.key, required this.cardId, required this.refMonth, required this.ofx});

  final String cardId;
  final DateTime refMonth;
  final String ofx;

  @override
  State<OfxImportScreen> createState() => _OfxImportScreenState();
}

class _OfxImportScreenState extends State<OfxImportScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<_Entry> _entries = [];
  List<Map<String, dynamic>> _notInFile = [];
  DateTime? _closingDate;
  DateTime? _fileStart;
  DateTime? _fileEnd;

  String get _base => '/cards/${widget.cardId}/invoices/${apiDate(widget.refMonth)}/ofx';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.description.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.post('$_base/preview', {'ofx': widget.ofx}) as Map<String, dynamic>;
      final stmt = data['statement'] as Map<String, dynamic>;
      setState(() {
        _entries = [for (final j in data['entries'] as List) _Entry(j as Map<String, dynamic>)];
        _notInFile = [for (final j in data['notInFile'] as List) j as Map<String, dynamic>];
        _closingDate = parseDate((data['invoice'] as Map)['closingDate'] as String);
        _fileStart = stmt['start'] == null ? null : parseDate(stmt['start'] as String);
        _fileEnd = stmt['end'] == null ? null : parseDate(stmt['end'] as String);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_Entry> _with(String status) => _entries.where((e) => e.status == status).toList();

  Future<void> _import() async {
    final news = _with('new');
    if (news.any((e) => e.include && e.description.text.trim().isEmpty)) {
      showSnack(context, 'Preencha o nome de todos os lançamentos marcados');
      return;
    }
    final api = context.read<Session>().api;
    final catalog = context.read<Catalog>();
    setState(() => _saving = true);
    try {
      final r = await api.post('$_base/import', {
        'ofx': widget.ofx,
        'items': [
          for (final e in news)
            {
              'index': e.index,
              'description': e.description.text.trim(),
              'categoryId': e.categoryId,
              'skip': !e.include,
            },
        ],
      }) as Map<String, dynamic>;
      await catalog.refresh();
      if (!mounted) return;
      showSnack(context, '${r['created']} lançamento(s) criado(s), ${r['linked']} conciliado(s)');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final news = _with('new');
    final toCreate = news.where((e) => e.include).fold<int>(0, (s, e) => s + e.creates);
    final linking = _with('matched').length;
    return Scaffold(
      appBar: AppBar(title: Text('Importar OFX · ${monthTitle(widget.refMonth)}')),
      body: _body(),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _saving || (toCreate == 0 && linking == 0) ? null : _import,
                  icon: _saving
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_done),
                  label: Text(toCreate == 0 ? 'Confirmar conciliação' : 'Importar $toCreate lançamento(s)'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final news = _with('new');
    final matched = _with('matched');
    final ignored = _with('ignored');
    final outOfPeriod = _fileEnd != null && _closingDate != null && (_fileEnd!.difference(_closingDate!).inDays).abs() > 7;

    Widget section(String title, [String? hint]) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall),
            if (hint != null) Text(hint, style: muted),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_entries.length} lançamentos no arquivo', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              if (_fileStart != null && _fileEnd != null)
                Text('Arquivo: ${shortDate(_fileStart!)} a ${shortDate(_fileEnd!)}/${_fileEnd!.year}', style: muted),
              if (_closingDate != null)
                Text('Fatura fecha em ${shortDate(_closingDate!)}/${_closingDate!.year}', style: muted),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                Chip(label: Text('${news.length} novos'), visualDensity: VisualDensity.compact),
                Chip(label: Text('${matched.length} já lançados'), visualDensity: VisualDensity.compact),
                if (ignored.isNotEmpty) Chip(label: Text('${ignored.length} ignorados'), visualDensity: VisualDensity.compact),
              ]),
              if (outOfPeriod) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'O período do arquivo não bate com o fechamento desta fatura. Confira se é a fatura certa.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ),
        if (news.isNotEmpty) ...[
          section('Novos (${news.length})', 'Revise o nome e a categoria. Desmarque o que não quer importar.'),
          for (final e in news) _NewEntryTile(entry: e, onChanged: () => setState(() {})),
        ],
        if (matched.isNotEmpty)
          ExpansionTile(
            title: Text('Já lançados (${matched.length})', style: theme.textTheme.titleSmall),
            subtitle: Text('Mesmo id, mesmo valor e data, ou mesma parcela. Nada será criado.', style: muted),
            children: [
              for (final e in matched)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.link),
                  title: Text(e.matchDescription ?? e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('No arquivo: ${e.memo} · ${shortDate(e.date)}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: _AmountText(entry: e),
                ),
            ],
          ),
        if (ignored.isNotEmpty) ...[
          section('Ignorados', 'Pagamento da fatura anterior: não é compra desta fatura.'),
          for (final e in ignored)
            ListTile(
              dense: true,
              leading: const Icon(Icons.block),
              title: Text(e.memo),
              subtitle: Text(shortDate(e.date)),
              trailing: _AmountText(entry: e),
            ),
        ],
        if (_notInFile.isNotEmpty)
          ExpansionTile(
            title: Text('No app, mas não no arquivo (${_notInFile.length})', style: theme.textTheme.titleSmall),
            subtitle: Text('Nada será alterado; confira se estão na fatura certa.', style: muted),
            children: [
              for (final t in _notInFile)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.help_outline),
                  title: Text(
                    t['installmentNumber'] == null
                        ? t['description'] as String
                        : '${t['description']}  ${t['installmentNumber']}/${t['installmentTotal']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(shortDate(parseDate(t['date'] as String))),
                  trailing: Text('${t['type'] == 'INCOME' ? '− ' : ''}${money(t['amount'] as int)}'),
                ),
            ],
          ),
      ],
    );
  }
}

class _AmountText extends StatelessWidget {
  const _AmountText({required this.entry});
  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    return Text(
      '${entry.isCredit ? '− ' : ''}${money(entry.amount)}',
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: entry.isCredit ? colors.income : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );
  }
}

class _NewEntryTile extends StatelessWidget {
  const _NewEntryTile({required this.entry, required this.onChanged});

  final _Entry entry;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final e = entry;
    final categories = context.watch<Catalog>().categories.where((c) => c.isIncome == e.isCredit).toList();
    final details = [
      shortDate(e.date),
      if (e.isCredit) 'Estorno',
      if (e.installmentLabel != null) e.installmentLabel!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Opacity(
        opacity: e.include ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(
              value: e.include,
              onChanged: (v) {
                e.include = v ?? false;
                onChanged();
              },
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text(details, style: muted)),
                  _AmountText(entry: e),
                ]),
                Text('No arquivo: ${e.memo}', style: muted, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (e.creates > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Cria ${e.creates} parcelas: ${e.installmentNumber} a ${e.installmentTotal} (esta e as próximas faturas)',
                      style: muted?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: e.description,
                  enabled: e.include,
                  decoration: const InputDecoration(labelText: 'Nome', isDense: true),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: categories.any((c) => c.id == e.categoryId) ? e.categoryId : null,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sem categoria')),
                    for (final c in categories)
                      DropdownMenuItem<String?>(
                        value: c.id,
                        child: Row(children: [
                          Icon(categoryIcon(c.icon), size: 18, color: hexColor(c.color)),
                          const SizedBox(width: 8),
                          Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                  ],
                  decoration: const InputDecoration(labelText: 'Categoria', isDense: true),
                  onChanged: e.include
                      ? (v) {
                          e.categoryId = v;
                          onChanged();
                        }
                      : null,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
