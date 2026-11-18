import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/money_field.dart';

class CardForm extends StatefulWidget {
  const CardForm({super.key, this.existing});

  final CardInfo? existing;

  static Future<bool?> open(BuildContext context, {CardInfo? existing}) => Navigator.of(context).push<bool>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => CardForm(existing: existing)),
      );

  @override
  State<CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<CardForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _limit = TextEditingController(
    text: widget.existing?.limit == null ? '' : centsToText(widget.existing!.limit!),
  );
  late int _closingDay = widget.existing?.closingDay ?? 1;
  late int _dueDay = widget.existing?.dueDay ?? 10;
  late bool _closingDayInNext = widget.existing?.closingDayInNext ?? true;
  late String? _paymentAccountId = widget.existing?.paymentAccountId;
  late String? _color = widget.existing?.color ?? swatches.first;
  late bool _archived = widget.existing?.archived ?? false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _paymentAccountId ??= context.read<Catalog>().activeAccounts.firstOrNull?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<Session>().api;
    final catalog = context.read<Catalog>();
    final limit = textToCents(_limit.text);
    final body = {
      'name': _name.text.trim(),
      'limit': limit == 0 ? null : limit,
      'closingDay': _closingDay,
      'dueDay': _dueDay,
      'closingDayInNext': _closingDayInNext,
      'paymentAccountId': _paymentAccountId,
      'color': _color,
      if (_isEdit) 'archived': _archived,
    };
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await api.put('/cards/${widget.existing!.id}', body);
      } else {
        await api.post('/cards', body);
      }
      await catalog.refresh();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final api = context.read<Session>().api;
    final catalog = context.read<Catalog>();
    final ok = await confirm(
      context,
      title: 'Excluir cartão',
      message: 'O cartão "${widget.existing!.name}", as faturas e TODAS as compras nele serão excluídos. '
          'Os pagamentos de fatura já lançados nas contas continuam. Para só esconder, use "Arquivado".',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await api.delete('/cards/${widget.existing!.id}');
      await catalog.refresh();
      if (!mounted) return;
      // Fecha o formulário e o detalhe do cartão que acabou de ser excluído.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = context.watch<Catalog>().activeAccounts;
    final days = [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('Dia $d'))];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar cartão' : 'Novo cartão'),
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
            TextFormField(
              controller: _name,
              autofocus: !_isEdit,
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Nubank Roxinho'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 16),
            MoneyField(controller: _limit, label: 'Limite (opcional)'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _closingDay,
                    items: days,
                    decoration: const InputDecoration(labelText: 'Fechamento'),
                    onChanged: (v) => setState(() => _closingDay = v ?? 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _dueDay,
                    items: days,
                    decoration: const InputDecoration(labelText: 'Vencimento'),
                    onChanged: (v) => setState(() => _dueDay = v ?? 10),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _closingDayInNext,
              onChanged: (v) => setState(() => _closingDayInNext = v),
              title: const Text('Compra no dia do fechamento vai para a próxima fatura'),
              subtitle: Text(_closingDayInNext
                  ? 'Compras feitas no dia $_closingDay já vão para a fatura seguinte'
                  : 'Compras feitas no dia $_closingDay ainda entram na fatura que está fechando'),
            ),
            if (_isEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Mudar fechamento/vencimento vale para as próximas compras. Faturas que já existem mantêm as datas.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: accounts.any((a) => a.id == _paymentAccountId) ? _paymentAccountId : null,
              items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
              decoration: const InputDecoration(
                labelText: 'Conta que paga a fatura',
                helperText: 'A fatura entra no saldo desta conta no vencimento',
              ),
              onChanged: (v) => setState(() => _paymentAccountId = v),
              validator: (v) => v == null ? 'Escolha a conta' : null,
            ),
            const SizedBox(height: 20),
            Text('Cor', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ColorChoice(value: _color, onChanged: (c) => setState(() => _color = c)),
            if (_isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _archived,
                onChanged: (v) => setState(() => _archived = v),
                title: const Text('Arquivado'),
                subtitle: const Text('Some das listas; o histórico continua'),
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
}
