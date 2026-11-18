import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../util/format.dart';
import '../util/invoice.dart';
import '../widgets/category_dropdown.dart';
import '../widgets/common.dart';
import '../widgets/money_field.dart';

enum _Repeat { none, installments, fixed }

/// Cadastro e edição de lançamento (simples, parcelado ou fixo).
class TransactionForm extends StatefulWidget {
  const TransactionForm({super.key, this.existing});

  final TxItem? existing;

  /// Abre o formulário; retorna true se salvou ou excluiu algo.
  static Future<bool?> open(BuildContext context, {TxItem? existing}) => Navigator.of(context).push<bool>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => TransactionForm(existing: existing)),
      );

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  final _installments = TextEditingController(text: '2');

  late TxType _type;
  late DateTime _date;
  bool _onCard = false;
  String? _accountId;
  String? _toAccountId;
  String? _cardId;
  String? _categoryId;
  bool _paid = true;
  bool _paidTouched = false;

  _Repeat _repeat = _Repeat.none;
  bool _installmentIsTotal = true;
  String _frequency = 'MONTHLY';
  DateTime? _endDate;

  bool _saving = false;

  TxItem? get _existing => widget.existing;
  bool get _isEdit => _existing != null;
  bool get _isGrouped => _existing?.recurrenceId != null || _existing?.installmentNumber != null;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    final catalog = context.read<Catalog>();
    final e = _existing;
    if (e != null) {
      _type = e.type;
      _amount.text = centsToText(e.amount);
      _description.text = e.description;
      _notes.text = e.notes ?? '';
      _date = e.date;
      _onCard = e.card != null;
      _accountId = e.account?.id;
      _toAccountId = e.toAccount?.id;
      _cardId = e.card?.id;
      _categoryId = e.category?.id;
      _paid = e.paid;
      _paidTouched = true;
    } else {
      _type = TxType.expense;
      _date = _today;
      final accounts = catalog.activeAccounts;
      _accountId = accounts.firstOrNull?.id;
      _toAccountId = accounts.length > 1 ? accounts[1].id : null;
      _cardId = catalog.activeCards.firstOrNull?.id;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _notes.dispose();
    _installments.dispose();
    super.dispose();
  }

  void _setType(TxType t) {
    final catalog = context.read<Catalog>();
    setState(() {
      _type = t;
      if (t == TxType.transfer) _onCard = false;
      final cat = catalog.categories.where((c) => c.id == _categoryId).firstOrNull;
      if (cat != null && cat.isIncome != (t == TxType.income)) _categoryId = null;
    });
  }

  void _setDate(DateTime d) {
    setState(() {
      _date = d;
      // Até o usuário mexer no "Pago", acompanha a data: passado = pago, futuro = pendente.
      if (!_paidTouched) _paid = !d.isAfter(_today);
    });
  }

  Future<void> _pickDate({bool end = false}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: end ? (_endDate ?? _date) : _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    if (end) {
      setState(() => _endDate = picked);
    } else {
      _setDate(picked);
    }
  }

  Future<String?> _askScope({required bool deleting}) => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(deleting ? 'Excluir quais?' : 'Aplicar a mudança em'),
          children: [
            if (!deleting)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Data, conta/cartão e status só mudam em "Só este".',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'one'), child: const Text('Só este')),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'future'), child: const Text('Este e os próximos')),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'all'), child: const Text('Todos')),
          ],
        ),
      );

  Map<String, dynamic> _fullBody(int cents) => {
        'description': _description.text.trim(),
        'amount': cents,
        'date': apiDate(_date),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        if (_type != TxType.transfer) 'categoryId': _categoryId,
        if (_type == TxType.transfer) ...{
          'accountId': _accountId,
          'toAccountId': _toAccountId,
          'status': _paid ? 'PAID' : 'PENDING',
        } else if (_onCard)
          'cardId': _cardId
        else ...{
          'accountId': _accountId,
          'status': _paid ? 'PAID' : 'PENDING',
        },
      };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<Session>().api;
    final catalog = context.read<Catalog>();
    final cents = textToCents(_amount.text);

    // Pergunta o escopo antes de mostrar o "salvando".
    var scope = 'one';
    if (_isEdit && _isGrouped) {
      final s = await _askScope(deleting: false);
      if (s == null) return;
      scope = s;
    }

    String? message;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final body = scope == 'one'
            ? _fullBody(cents)
            : {
                'description': _description.text.trim(),
                'amount': cents,
                'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                if (_type != TxType.transfer) 'categoryId': _categoryId,
              };
        await api.put('/transactions/${_existing!.id}', body, query: {'scope': scope});
      } else {
        final body = {
          'type': switch (_type) {
            TxType.income => 'INCOME',
            TxType.expense => 'EXPENSE',
            TxType.transfer => 'TRANSFER',
          },
          ..._fullBody(cents),
          if (_repeat == _Repeat.installments)
            'installments': {
              'total': int.parse(_installments.text),
              'amountIs': _installmentIsTotal ? 'total' : 'each',
            },
          if (_repeat == _Repeat.fixed)
            'recurrence': {
              'frequency': _frequency,
              if (_endDate != null) 'endDate': apiDate(_endDate!),
            },
        };
        final res = await api.post('/transactions', body) as Map<String, dynamic>;
        final count = res['count'] as int;
        if (count > 1) message = '$count lançamentos criados';
      }
      await catalog.refresh();
      if (!mounted) return;
      if (message != null) showSnack(context, message);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final api = context.read<Session>().api;
    final catalog = context.read<Catalog>();
    var scope = 'one';
    if (_isGrouped) {
      final s = await _askScope(deleting: true);
      if (s == null) return;
      scope = s;
    } else {
      if (!mounted) return;
      final ok = await confirm(
        context,
        title: 'Excluir lançamento',
        message: '"${_existing!.description}" será excluído.',
        confirmLabel: 'Excluir',
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      await api.delete('/transactions/${_existing!.id}', query: {'scope': scope});
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
    final catalog = context.watch<Catalog>();
    final theme = Theme.of(context);
    final accounts = catalog.activeAccounts;
    final cards = catalog.activeCards;
    final card = catalog.card(_cardId);

    if (accounts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Novo lançamento')),
        body: const EmptyView(
          icon: Icons.account_balance_outlined,
          message: 'Cadastre uma conta na aba Contas antes de lançar.',
        ),
      );
    }

    final accountItems = [
      for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
      // Mantém visível uma conta arquivada já usada no lançamento.
      if (_accountId != null && accounts.every((a) => a.id != _accountId))
        DropdownMenuItem(value: _accountId, child: Text(catalog.account(_accountId)?.name ?? 'Conta')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar lançamento' : 'Novo lançamento'),
        actions: [
          if (_isEdit)
            IconButton(tooltip: 'Excluir', onPressed: _saving ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SegmentedButton<TxType>(
              segments: const [
                ButtonSegment(value: TxType.expense, label: Text('Despesa'), icon: Icon(Icons.south_west)),
                ButtonSegment(value: TxType.income, label: Text('Receita'), icon: Icon(Icons.north_east)),
                ButtonSegment(value: TxType.transfer, label: Text('Transf.'), icon: Icon(Icons.swap_horiz)),
              ],
              selected: {_type},
              onSelectionChanged: _isEdit ? null : (s) => _setType(s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            MoneyField(
              controller: _amount,
              label: _repeat == _Repeat.installments && _installmentIsTotal ? 'Valor total' : 'Valor',
              autofocus: !_isEdit,
              style: theme.textTheme.headlineSmall,
              validator: (c) => c <= 0 ? 'Informe o valor' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Descrição'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe uma descrição' : null,
            ),
            const SizedBox(height: 16),
            _DateRow(
              date: _date,
              today: _today,
              onPick: () => _pickDate(),
              onSelect: _setDate,
            ),
            const SizedBox(height: 16),
            if (_type == TxType.transfer) ...[
              DropdownButtonFormField<String>(
                key: const ValueKey('from'),
                initialValue: _accountId,
                items: accountItems,
                decoration: const InputDecoration(labelText: 'De (conta de origem)'),
                onChanged: (v) => setState(() => _accountId = v),
                validator: (v) => v == null ? 'Escolha a conta' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('to'),
                initialValue: _toAccountId,
                items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                decoration: const InputDecoration(labelText: 'Para (conta de destino)'),
                onChanged: (v) => setState(() => _toAccountId = v),
                validator: (v) => v == null
                    ? 'Escolha a conta'
                    : v == _accountId
                        ? 'Escolha uma conta diferente da origem'
                        : null,
              ),
            ] else ...[
              if (cards.isNotEmpty || _onCard) ...[
                SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: false, label: Text('Conta'), icon: Icon(Icons.account_balance_outlined)),
                    ButtonSegment(
                      value: true,
                      label: Text(_type == TxType.income ? 'Cartão (estorno)' : 'Cartão'),
                      icon: const Icon(Icons.credit_card),
                    ),
                  ],
                  selected: {_onCard},
                  onSelectionChanged: (s) => setState(() => _onCard = s.first),
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 16),
              ],
              if (_onCard)
                DropdownButtonFormField<String>(
                  key: const ValueKey('card'),
                  initialValue: _cardId,
                  items: [for (final c in catalog.cards) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  decoration: InputDecoration(
                    labelText: 'Cartão',
                    helperText: card == null ? null : 'Entra na fatura que vence em ${shortDate(invoiceDueFor(_date, card))}',
                  ),
                  onChanged: (v) => setState(() => _cardId = v),
                  validator: (v) => v == null ? 'Escolha o cartão' : null,
                )
              else
                DropdownButtonFormField<String>(
                  key: const ValueKey('account'),
                  initialValue: _accountId,
                  items: accountItems,
                  decoration: const InputDecoration(labelText: 'Conta'),
                  onChanged: (v) => setState(() => _accountId = v),
                  validator: (v) => v == null ? 'Escolha a conta' : null,
                ),
              const SizedBox(height: 16),
              CategoryDropdown(
                income: _type == TxType.income,
                value: _categoryId,
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            if (!_onCard)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _paid,
                onChanged: (v) => setState(() {
                  _paid = v;
                  _paidTouched = true;
                }),
                title: Text(switch (_type) {
                  TxType.income => 'Recebido',
                  TxType.expense => 'Pago',
                  TxType.transfer => 'Realizada',
                }),
                subtitle: Text(_repeat == _Repeat.none
                    ? 'Desligado = pendente (entra só no saldo previsto)'
                    : 'Vale para as ocorrências até hoje; as futuras ficam pendentes'),
              ),
            if (!_isEdit) ...[
              const SizedBox(height: 8),
              Text('Repetição', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<_Repeat>(
                segments: const [
                  ButtonSegment(value: _Repeat.none, label: Text('Não repete')),
                  ButtonSegment(value: _Repeat.installments, label: Text('Parcelado')),
                  ButtonSegment(value: _Repeat.fixed, label: Text('Fixo')),
                ],
                selected: {_repeat},
                onSelectionChanged: (s) => setState(() => _repeat = s.first),
                showSelectedIcon: false,
              ),
              if (_repeat == _Repeat.installments) ..._installmentFields(theme),
              if (_repeat == _Repeat.fixed) ..._fixedFields(theme),
            ],
            if (_isEdit && _isGrouped)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(_existing!.isFixed ? Icons.repeat : Icons.view_week_outlined),
                    title: Text(_existing!.isFixed
                        ? 'Lançamento fixo'
                        : 'Parcela ${_existing!.installmentNumber}/${_existing!.installmentTotal}'),
                    subtitle: const Text('Ao salvar ou excluir, você escolhe se vale só para este ou também para os outros.'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Observação (opcional)'),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _installmentFields(ThemeData theme) {
    final n = int.tryParse(_installments.text) ?? 0;
    final cents = textToCents(_amount.text);
    String? preview;
    if (n >= 2 && cents > 0) {
      preview = _installmentIsTotal
          ? '$n× de ${money(cents ~/ n)} (total ${money(cents)})'
          : '$n× de ${money(cents)} (total ${money(cents * n)})';
    }
    return [
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: TextFormField(
              controller: _installments,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Parcelas'),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final x = int.tryParse(v ?? '');
                return x == null || x < 2 || x > 360 ? '2 a 360' : null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Valor total')),
                ButtonSegment(value: false, label: Text('Cada parcela')),
              ],
              selected: {_installmentIsTotal},
              onSelectionChanged: (s) => setState(() => _installmentIsTotal = s.first),
              showSelectedIcon: false,
            ),
          ),
        ],
      ),
      if (preview != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(preview, style: theme.textTheme.bodySmall),
        ),
      if (_onCard)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Cada parcela vai para a fatura do mês seguinte.', style: theme.textTheme.bodySmall),
        ),
    ];
  }

  List<Widget> _fixedFields(ThemeData theme) => [
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _frequency,
          items: const [
            DropdownMenuItem(value: 'MONTHLY', child: Text('Todo mês')),
            DropdownMenuItem(value: 'WEEKLY', child: Text('Toda semana')),
            DropdownMenuItem(value: 'YEARLY', child: Text('Todo ano')),
          ],
          decoration: const InputDecoration(labelText: 'Frequência'),
          onChanged: (v) => setState(() => _frequency = v ?? 'MONTHLY'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _endDate != null,
          onChanged: (v) {
            if (v) {
              _pickDate(end: true);
            } else {
              setState(() => _endDate = null);
            }
          },
          title: const Text('Tem data final'),
          subtitle: Text(_endDate == null
              ? 'Sem data final: o app mantém os próximos 12 meses lançados'
              : 'Até ${shortDate(_endDate!)}/${_endDate!.year}'),
        ),
        if (_endDate != null && _endDate!.isBefore(_date))
          Text('A data final é antes da data inicial', style: TextStyle(color: theme.colorScheme.error)),
      ];
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date, required this.today, required this.onPick, required this.onSelect});

  final DateTime date;
  final DateTime today;
  final VoidCallback onPick;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final yesterday = today.subtract(const Duration(days: 1));
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text('${dayTitle(date)} de ${date.year}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), alignment: Alignment.centerLeft),
          ),
        ),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('Hoje'), selected: sameDay(date, today), onSelected: (_) => onSelect(today)),
        const SizedBox(width: 6),
        ChoiceChip(label: const Text('Ontem'), selected: sameDay(date, yesterday), onSelected: (_) => onSelect(yesterday)),
      ],
    );
  }
}
