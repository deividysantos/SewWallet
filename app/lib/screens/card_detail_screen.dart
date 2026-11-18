import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/money_field.dart';
import '../widgets/stitch.dart';
import 'card_form.dart';
import 'cards_screen.dart';
import 'ofx_import_screen.dart';

String _refLabel(DateTime ref) {
  final s = DateFormat('MMMM yyyy', 'pt_BR').format(ref);
  return s[0].toUpperCase() + s.substring(1);
}

/// Faturas de um cartão: total, situação, compras e pagamento.
class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.cardId, this.invoiceId});

  final String cardId;
  final String? invoiceId;

  static Future<void> open(BuildContext context, {required String cardId, String? invoiceId}) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: cardId, invoiceId: invoiceId)),
      );

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  List<InvoiceSummary> _invoices = [];
  int _index = 0;
  InvoiceSummary? _invoice;
  List<InvoiceEntry> _items = [];
  List<InvoiceEntry> _payments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvoices(selectId: widget.invoiceId);
  }

  Future<void> _loadInvoices({String? selectId}) async {
    final api = context.read<Session>().api;
    final card = context.read<Catalog>().card(widget.cardId);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.get('/cards/${widget.cardId}/invoices') as List;
      final invoices = [for (final j in list) InvoiceSummary.fromJson(j as Map<String, dynamic>)];
      var index = invoices.indexWhere((i) => i.id == (selectId ?? _invoice?.id));
      if (index < 0 && card != null) {
        // Fatura atual; se ela ainda não tem compras, a próxima depois dela.
        final ref = card.currentInvoice.refMonth;
        index = invoices.indexWhere((i) => !i.refMonth.isBefore(ref));
      }
      if (index < 0) index = invoices.length - 1;
      setState(() {
        _invoices = invoices;
        _index = index;
      });
      await _loadDetail();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDetail() async {
    if (_index < 0 || _index >= _invoices.length) {
      setState(() => _invoice = null);
      return;
    }
    final id = _invoices[_index].id!;
    final data = await context.read<Session>().api.get('/invoices/$id') as Map<String, dynamic>;
    if (!mounted) return;
    setState(() {
      _invoice = InvoiceSummary.fromJson(data);
      _items = [for (final j in data['items'] as List) InvoiceEntry.fromJson(j as Map<String, dynamic>)];
      _payments = [for (final j in data['payments'] as List) InvoiceEntry.fromJson(j as Map<String, dynamic>)];
    });
  }

  Future<void> _go(int delta) async {
    final next = _index + delta;
    if (next < 0 || next >= _invoices.length) return;
    setState(() {
      _index = next;
      _loading = true;
    });
    try {
      await _loadDetail();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay(CardInfo card) async {
    final inv = _invoice!;
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PaySheet(invoiceId: inv.id!, remaining: inv.remaining, defaultAccountId: card.paymentAccountId),
    );
    if (paid == true && mounted) {
      showSnack(context, 'Pagamento lançado');
      await _loadInvoices(selectId: inv.id);
    }
  }

  Future<void> _importOfx(DateTime refMonth) async {
    final currentId = _invoice?.id;
    try {
      final imported = await pickAndImportOfx(context, cardId: widget.cardId, refMonth: refMonth);
      if (!imported || !mounted) return;
      // Fica na fatura importada (ela pode ter acabado de ser criada).
      final list = await context.read<Session>().api.get('/cards/${widget.cardId}/invoices') as List;
      final target = list
          .map((j) => InvoiceSummary.fromJson(j as Map<String, dynamic>))
          .where((i) => i.refMonth.year == refMonth.year && i.refMonth.month == refMonth.month)
          .firstOrNull;
      await _loadInvoices(selectId: target?.id ?? currentId);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<Catalog>();
    final card = catalog.card(widget.cardId);
    if (card == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyView(icon: Icons.credit_card_off, message: 'Cartão não encontrado'));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(card.name),
        actions: [
          IconButton(
            tooltip: 'Editar cartão',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await CardForm.open(context, existing: card);
              if (mounted) _loadInvoices();
            },
          ),
        ],
      ),
      body: _body(card),
    );
  }

  Widget _body(CardInfo card) {
    if (_error != null && _invoice == null) return ErrorView(message: _error!, onRetry: _loadInvoices);
    if (_loading && _invoice == null) return const Center(child: CircularProgressIndicator());
    if (_invoices.isEmpty || _invoice == null) {
      return Column(
        children: [
          const Expanded(
            child: EmptyView(icon: Icons.receipt_long_outlined, message: 'Nenhuma compra neste cartão ainda.'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: OutlinedButton.icon(
              onPressed: () => _importOfx(card.currentInvoice.refMonth),
              icon: const Icon(Icons.upload_file),
              label: Text('Importar OFX na fatura de ${_refLabel(card.currentInvoice.refMonth)}'),
            ),
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final inv = _invoice!;
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget info(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: muted),
            Text(value, style: theme.textTheme.bodyMedium),
          ]),
        );

    return RefreshIndicator(
      onRefresh: () => _loadInvoices(selectId: inv.id),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Fatura anterior',
                onPressed: _index > 0 ? () => _go(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(
                  'Fatura de ${_refLabel(inv.refMonth)}',
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Próxima fatura',
                onPressed: _index < _invoices.length - 1 ? () => _go(1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          StitchedCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          money(inv.total),
                          style: theme.textTheme.headlineMedium?.copyWith(color: colors.expense, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Chip(
                        label: Text(invoiceStatusLabel(inv.status)),
                        labelStyle: TextStyle(color: invoiceStatusColor(context, inv.status)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    info('Fecha', '${shortDate(inv.closingDate)}/${inv.closingDate.year}'),
                    info('Vence', '${shortDate(inv.dueDate)}/${inv.dueDate.year}'),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    info('Pago', money(inv.paid)),
                    info('Falta pagar', money(inv.remaining)),
                  ]),
                  if (inv.remaining > 0) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _pay(card),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(inv.status == InvoiceStatus.open ? 'Antecipar pagamento' : 'Pagar fatura'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _importOfx(inv.refMonth),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Importar arquivo OFX'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Compras (${_items.length})', style: theme.textTheme.titleSmall),
          ),
          for (final it in _items)
            ListTile(
              leading: IconBadge(icon: categoryIcon(it.category?.icon), color: hexColor(it.category?.color)),
              title: Text(
                it.installmentNumber == null ? it.description : '${it.description}  ${it.installmentNumber}/${it.installmentTotal}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${shortDate(it.date)} · ${it.category?.name ?? 'Sem categoria'}'),
              trailing: Text(
                '${it.isCredit ? '− ' : ''}${money(it.amount)}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: it.isCredit ? colors.income : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (_payments.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Pagamentos', style: theme.textTheme.titleSmall),
            ),
            for (final p in _payments)
              ListTile(
                leading: IconBadge(icon: Icons.payments_outlined, color: colors.income),
                title: Text(p.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${shortDate(p.date)} · ${p.paid ? 'pago' : 'agendado'}'),
                trailing: Text(money(p.amount)),
              ),
          ],
        ],
      ),
    );
  }
}

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.invoiceId, required this.remaining, required this.defaultAccountId});

  final String invoiceId;
  final int remaining;
  final String defaultAccountId;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: centsToText(widget.remaining));
  late String? _accountId = widget.defaultAccountId;
  DateTime _date = DateTime.now();
  bool _paid = true;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<Session>().api;
    final catalog = context.read<Catalog>();
    setState(() => _saving = true);
    try {
      await api.post('/invoices/${widget.invoiceId}/payments', {
        'amount': textToCents(_amount.text),
        'accountId': _accountId,
        'date': apiDate(_date),
        'status': _paid ? 'PAID' : 'PENDING',
      });
      await catalog.refresh();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<Catalog>().activeAccounts;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pagar fatura', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Falta pagar ${money(widget.remaining)}. Pode pagar só uma parte.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            MoneyField(
              controller: _amount,
              validator: (c) => c <= 0 ? 'Informe o valor' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: accounts.any((a) => a.id == _accountId) ? _accountId : null,
              items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
              decoration: const InputDecoration(labelText: 'Pagar com a conta'),
              onChanged: (v) => setState(() => _accountId = v),
              validator: (v) => v == null ? 'Escolha a conta' : null,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _date = d);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('Data: ${dayTitle(_date)} de ${_date.year}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _paid,
              onChanged: (v) => setState(() => _paid = v),
              title: const Text('Já foi pago'),
              subtitle: const Text('Desligado = agendado (entra só no saldo previsto)'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Lançar pagamento'),
            ),
          ],
        ),
      ),
    );
  }
}
