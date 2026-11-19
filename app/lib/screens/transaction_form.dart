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

/// Cadastro e edição de lançamento (simples, parcelado ou fixo) ou de previsão.
class TransactionForm extends StatefulWidget {
  const TransactionForm({
    super.key,
    this.existing,
    this.abate,
    this.forecast = false,
    this.type,
    this.card = false,
    this.suggestion,
  });

  final TxItem? existing;

  /// Criar o lançamento a partir de uma notificação de banco: vem preenchido e, ao salvar,
  /// a sugestão é marcada como aceita.
  final SuggestionItem? suggestion;

  /// Lançar o valor real de uma previsão: o formulário vem preenchido e vinculado a ela.
  final TxItem? abate;

  /// Novo lançamento já marcado como previsão.
  final bool forecast;

  /// Tipo escolhido no botão "+" (sem ele, o formulário mostra a escolha Despesa/Receita).
  final TxType? type;

  /// Compra no cartão (botão "Cartão" do "+").
  final bool card;

  /// Abre o formulário; retorna true se salvou ou excluiu algo.
  static Future<bool?> open(
    BuildContext context, {
    TxItem? existing,
    TxItem? abate,
    bool forecast = false,
    TxType? type,
    bool card = false,
    SuggestionItem? suggestion,
  }) => Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TransactionForm(
        existing: existing,
        abate: abate,
        forecast: forecast,
        type: suggestion?.type ?? type,
        card: suggestion?.cardId != null || card,
        suggestion: suggestion,
      ),
    ),
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

  /// É uma previsão (valor estimado).
  bool _isForecast = false;

  /// Lançamento real: previsão que ele abate.
  TxItem? _forecast;
  String? _forecastId;

  /// Encerrar a previsão depois de salvar o valor real.
  bool _closeForecast = false;

  /// Gerar (ou manter) a contrapartida ligada: tipo oposto, mesmo valor, zera o lançamento.
  bool _counterpart = false;

  /// Contrapartida só em despesa/receita real, que não seja ela mesma uma contrapartida nem pagamento de fatura.
  bool get _canCounterpart =>
      !_isForecast &&
      _type != TxType.transfer &&
      !(_existing?.isCounterpart ?? false) &&
      _existing?.paysInvoiceId == null;

  TxItem? get _existing => widget.existing;
  bool get _isEdit => _existing != null;
  bool get _chooseType => !_isEdit && widget.type == null && widget.abate == null && !widget.card;
  bool get _isGrouped => _existing?.recurrenceId != null || _existing?.installmentNumber != null;
  bool get _canAbate => !_isForecast && _type != TxType.transfer && _repeat == _Repeat.none;

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
      _isForecast = e.isForecast;
      _forecastId = e.forecastId;
      _counterpart = e.hasCounterpart;
      if (e.isForecast) _amount.text = centsToText(e.forecast!.planned);
    } else if (widget.abate != null) {
      // Valor real de uma previsão: mesmos dados, valor = o que falta abater, data = hoje.
      final f = widget.abate!;
      _type = f.type;
      _amount.text = centsToText(f.forecast?.remaining ?? f.amount);
      _description.text = f.description;
      _date = _today;
      _onCard = f.card != null;
      _accountId = f.account?.id ?? catalog.activeAccounts.firstOrNull?.id;
      _cardId = f.card?.id ?? catalog.activeCards.firstOrNull?.id;
      _categoryId = f.category?.id;
      _forecast = f;
      _forecastId = f.id;
    } else {
      _type = widget.type ?? TxType.expense;
      _onCard = widget.card && catalog.activeCards.isNotEmpty;
      _date = _today;
      _isForecast = widget.forecast;
      final accounts = catalog.activeAccounts;
      _accountId = accounts.firstOrNull?.id;
      _toAccountId = accounts.length > 1 ? accounts[1].id : null;
      _cardId = catalog.activeCards.firstOrNull?.id;
      final s = widget.suggestion;
      if (s != null) {
        // O que a IA entendeu da notificação; o usuário confere e salva.
        if (s.amount != null) _amount.text = centsToText(s.amount!);
        _description.text = s.description ?? s.merchant ?? '';
        if (s.date != null) _date = s.date!;
        _paid = !_date.isAfter(_today);
        if (s.cardId != null && catalog.card(s.cardId) != null) _cardId = s.cardId;
        if (s.accountId != null && catalog.account(s.accountId) != null) _accountId = s.accountId;
        if (_accountId == _toAccountId) _toAccountId = accounts.where((a) => a.id != _accountId).firstOrNull?.id;
        if (s.categoryId != null && catalog.categories.any((c) => c.id == s.categoryId)) _categoryId = s.categoryId;
        if (s.installments != null && s.installments! >= 2 && _onCard) {
          _repeat = _Repeat.installments;
          _installments.text = '${s.installments}';
        }
      }
    }
    if (_forecastId != null && _forecast == null) _loadLinkedForecast();
  }

  /// Edição de um lançamento que abate uma previsão: busca os dados dela para mostrar.
  Future<void> _loadLinkedForecast() async {
    try {
      final j = await context.read<Session>().api.get('/transactions/$_forecastId');
      if (mounted) setState(() => _forecast = TxItem.fromJson(j as Map<String, dynamic>));
    } catch (_) {}
  }

  Future<void> _pickForecast() async {
    final api = context.read<Session>().api;
    List<TxItem> open;
    try {
      final j =
          await api.get('/transactions/forecasts/open', query: {'type': _type == TxType.income ? 'INCOME' : 'EXPENSE'})
              as List;
      open = [for (final x in j) TxItem.fromJson(x as Map<String, dynamic>)];
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
      return;
    }
    // As da mesma categoria primeiro, depois por data.
    open.sort((a, b) {
      final ca = a.category?.id == _categoryId ? 0 : 1;
      final cb = b.category?.id == _categoryId ? 0 : 1;
      return ca != cb ? ca - cb : a.date.compareTo(b.date);
    });
    if (!mounted) return;
    final picked = await showModalBottomSheet<TxItem>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: open.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('Nenhuma previsão aberta deste tipo.'))
            : ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Abater de qual previsão?')),
                  for (final f in open)
                    ListTile(
                      leading: const Icon(Icons.insights_outlined),
                      title: Text(f.description),
                      subtitle: Text(
                        'até ${shortDate(f.date)} · ${f.category?.name ?? 'Sem categoria'} · '
                        '${f.card?.name ?? f.account?.name ?? ''}',
                      ),
                      trailing: Text('resta ${money(f.forecast!.remaining)}'),
                      onTap: () => Navigator.pop(ctx, f),
                    ),
                ],
              ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _forecast = picked;
      _forecastId = picked.id;
      if (_categoryId == null && picked.category != null) _categoryId = picked.category!.id;
      if (_description.text.trim().isEmpty) _description.text = picked.description;
    });
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
      if (t == TxType.transfer) {
        _onCard = false;
        _isForecast = false;
      }
      if (_forecast != null && _forecast!.type != t) {
        _forecast = null;
        _forecastId = null;
      }
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
            child: Text('Data, conta/cartão e status só mudam em "Só este".', style: Theme.of(ctx).textTheme.bodySmall),
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
      if (!_isForecast) 'status': _paid ? 'PAID' : 'PENDING',
    },
    if (!_isForecast && _type != TxType.transfer && (_isEdit || _repeat == _Repeat.none)) 'forecastId': _forecastId,
    if (_canCounterpart && (_isEdit ? _counterpart != _existing!.hasCounterpart : _counterpart))
      'counterpart': _counterpart,
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
          if (_isForecast) 'isForecast': true,
          if (_repeat == _Repeat.installments)
            'installments': {
              'total': int.parse(_installments.text),
              'amountIs': _installmentIsTotal ? 'total' : 'each',
            },
          if (_repeat == _Repeat.fixed)
            'recurrence': {'frequency': _frequency, if (_endDate != null) 'endDate': apiDate(_endDate!)},
        };
        final res = await api.post('/transactions', body) as Map<String, dynamic>;
        final count = res['count'] as int;
        if (count > 1) message = _isForecast ? '$count previsões criadas' : '$count lançamentos criados';
        final s = widget.suggestion;
        if (s != null) {
          final created = (res['transactions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          await api.post('/suggestions/${s.id}/accept', {'transactionId': created.firstOrNull?['id']});
          message ??= 'Lançamento criado a partir da notificação';
        }
      }
      if (_closeForecast && _forecastId != null) {
        await api.patch('/transactions/$_forecastId/forecast-state', {'state': 'CLOSED'});
        message ??= 'Previsão encerrada';
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
        message: _existing!.isCounterpart
            ? '"${_existing!.description}" e o lançamento de origem serão excluídos.'
            : _existing!.hasCounterpart
            ? '"${_existing!.description}" e a sua contrapartida serão excluídos.'
            : '"${_existing!.description}" será excluído.',
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
        title: Text(
          _isForecast
              ? '${_isEdit ? 'Editar previsão' : 'Previsão'} a ${_type == TxType.income ? 'receber' : 'pagar'}'
              : _isEdit
              ? 'Editar lançamento'
              : _onCard
              ? 'Compra no cartão'
              : switch (_type) {
                  TxType.expense => 'Nova despesa',
                  TxType.income => 'Nova receita',
                  TxType.transfer => 'Nova transferência',
                },
        ),
        actions: [
          if (_isEdit)
            IconButton(tooltip: 'Excluir', onPressed: _saving ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Form(
        key: _form,
        // Column (não ListView): todos os campos ficam montados, então a validação vale até
        // para os que rolaram para fora da tela.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // O tipo vem do botão "+"; a escolha só aparece quando o formulário abre sem ele
              // (ex.: "Nova previsão"), e sem transferência e cartão.
              if (_chooseType)
                SegmentedButton<TxType>(
                  segments: const [
                    ButtonSegment(value: TxType.expense, label: Text('Despesa'), icon: Icon(Icons.arrow_downward)),
                    ButtonSegment(value: TxType.income, label: Text('Receita'), icon: Icon(Icons.arrow_upward)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => _setType(s.first),
                  showSelectedIcon: false,
                ),
              if (_type != TxType.transfer)
                SwitchListTile(
                  key: const ValueKey('forecastSwitch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.insights_outlined),
                  value: _isForecast,
                  onChanged: _isEdit || widget.abate != null
                      ? null
                      : (v) => setState(() {
                          _isForecast = v;
                          if (v) {
                            if (_repeat == _Repeat.installments) _repeat = _Repeat.none;
                            _forecast = null;
                            _forecastId = null;
                          }
                        }),
                  title: const Text('É uma previsão'),
                  subtitle: Text(
                    _isForecast
                        ? 'Valor estimado até a data. Os lançamentos reais abatem dele; '
                              'se a data passar, a previsão expira'
                        : 'Desligado = lançamento real',
                  ),
                ),
              const SizedBox(height: 8),
              MoneyField(
                controller: _amount,
                label: _isForecast
                    ? 'Valor previsto'
                    : _repeat == _Repeat.installments && _installmentIsTotal
                    ? 'Valor total'
                    : 'Valor',
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
              _DateRow(date: _date, today: _today, onPick: () => _pickDate(), onSelect: _setDate),
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
                if (_onCard)
                  DropdownButtonFormField<String>(
                    key: const ValueKey('card'),
                    initialValue: _cardId,
                    items: [for (final c in catalog.cards) DropdownMenuItem(value: c.id, child: Text(c.name))],
                    decoration: InputDecoration(
                      labelText: 'Cartão',
                      helperText: card == null
                          ? null
                          : 'Entra na fatura que vence em ${shortDate(invoiceDueFor(_date, card))}',
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
              if (_canAbate) _abateTile(theme),
              if (_existing?.isCounterpart ?? false) _counterpartInfo(),
              if (_canCounterpart) _counterpartTile(catalog),
              if (_isForecast && _isEdit && _existing!.forecast != null) _forecastInfo(theme, _existing!.forecast!),
              if (!_onCard && !_isForecast)
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
                  subtitle: Text(
                    _repeat == _Repeat.none
                        ? 'Desligado = pendente (entra só no saldo previsto)'
                        : 'Vale para as ocorrências até hoje; as futuras ficam pendentes',
                  ),
                ),
              if (!_isEdit) ...[
                const SizedBox(height: 8),
                Text('Repetição', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<_Repeat>(
                  segments: [
                    const ButtonSegment(value: _Repeat.none, label: Text('Não repete')),
                    ButtonSegment(value: _Repeat.installments, label: const Text('Parcelado'), enabled: !_isForecast),
                    const ButtonSegment(value: _Repeat.fixed, label: Text('Fixo')),
                  ],
                  selected: {_repeat},
                  onSelectionChanged: (s) => setState(() {
                    _repeat = s.first;
                    if (_repeat != _Repeat.none) {
                      _forecast = null;
                      _forecastId = null;
                    }
                  }),
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
                      title: Text(
                        _existing!.isFixed
                            ? 'Lançamento fixo'
                            : 'Parcela ${_existing!.installmentNumber}/${_existing!.installmentTotal}',
                      ),
                      subtitle: const Text(
                        'Ao salvar ou excluir, você escolhe se vale só para este ou também para os outros.',
                      ),
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
      ),
    );
  }

  /// Lançamento real: escolher a previsão que ele abate.
  Widget _abateTile(ThemeData theme) {
    final f = _forecast;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: Column(
          children: [
            ListTile(
              key: const ValueKey('abateTile'),
              leading: const Icon(Icons.insights_outlined),
              title: Text(f == null ? 'Abater de uma previsão (opcional)' : 'Abate de: ${f.description}'),
              subtitle: f == null
                  ? const Text('O valor deste lançamento sai do que falta da previsão')
                  : f.forecast == null
                  ? null
                  : Text(
                      'até ${shortDate(f.date)} · previsto ${money(f.forecast!.planned)} · '
                      'resta ${money(f.forecast!.remaining)}',
                    ),
              trailing: f == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      tooltip: 'Desvincular',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _forecast = null;
                        _forecastId = null;
                        _closeForecast = false;
                      }),
                    ),
              onTap: _pickForecast,
            ),
            if (_forecastId != null && !_isEdit)
              CheckboxListTile(
                key: const ValueKey('closeForecast'),
                value: _closeForecast,
                onChanged: (v) => setState(() => _closeForecast = v ?? false),
                title: const Text('Encerrar a previsão após salvar'),
                subtitle: const Text('O que sobrar dela deixa de contar nos saldos'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _counterpartTile(Catalog catalog) {
    final card = _onCard ? catalog.card(_cardId) : null;
    final opposite = _type == TxType.expense ? 'Receita' : 'Despesa';
    final where = card != null
        ? 'na conta ${catalog.account(card.paymentAccountId)?.name ?? 'que paga a fatura'}, '
              'no vencimento da fatura (${shortDate(invoiceDueFor(_date, card))})'
        : 'na mesma conta e data';
    return SwitchListTile(
      key: const ValueKey('counterpartSwitch'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.compare_arrows),
      value: _counterpart,
      onChanged: (v) => setState(() => _counterpart = v),
      title: const Text('Gerar contrapartida'),
      subtitle: Text(
        _counterpart
            ? '$opposite de mesmo valor $where, "Compensação de: ...". '
                  'Valor e data andam juntos; excluir um exclui o outro'
            : 'Ex.: compra para alguém que vai te pagar depois',
      ),
    );
  }

  Widget _counterpartInfo() => const Padding(
    padding: EdgeInsets.only(top: 8),
    child: Card(
      child: ListTile(
        leading: Icon(Icons.compare_arrows),
        title: Text('Contrapartida'),
        subtitle: Text(
          'Ligada ao lançamento de origem: o valor muda lá também (a data, se a origem é '
          'em conta), e excluir esta exclui a origem.',
        ),
      ),
    ),
  );

  Widget _forecastInfo(ThemeData theme, ForecastInfo f) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Card(
      child: ListTile(
        leading: const Icon(Icons.insights_outlined),
        title: Text(switch (f.state) {
          ForecastState.open => 'Previsão aberta',
          ForecastState.closed => 'Previsão encerrada',
          ForecastState.expired => 'Previsão expirada',
        }),
        subtitle: Text('Previsto ${money(f.planned)} · abatido ${money(f.abated)} · resta ${money(f.remaining)}'),
      ),
    ),
  );

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
      subtitle: Text(
        _endDate == null
            ? 'Sem data final: o app mantém os próximos 12 meses lançados'
            : 'Até ${shortDate(_endDate!)}/${_endDate!.year}',
      ),
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
        ChoiceChip(
          label: const Text('Ontem'),
          selected: sameDay(date, yesterday),
          onSelected: (_) => onSelect(yesterday),
        ),
      ],
    );
  }
}
