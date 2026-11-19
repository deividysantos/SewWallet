import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/money_field.dart';
import '../widgets/stitch.dart';
import 'categories_screen.dart';

IconData accountIcon(String type) => switch (type) {
  'SAVINGS' => Icons.savings_outlined,
  'WALLET' => Icons.account_balance_wallet_outlined,
  'INVESTMENT' => Icons.trending_up,
  'OTHER' => Icons.folder_outlined,
  _ => Icons.account_balance_outlined,
};

/// Contas com saldo atual e previsto para o fim do mês.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<Catalog>();
    final theme = Theme.of(context);
    final active = catalog.activeAccounts;
    final archived = catalog.accounts.where((a) => a.archived).toList();
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget body;
    if (!catalog.loaded && catalog.error != null) {
      body = ErrorView(message: catalog.error!, onRetry: catalog.refresh);
    } else if (!catalog.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (catalog.accounts.isEmpty) {
      body = EmptyView(
        icon: Icons.account_balance_outlined,
        message: 'Nenhuma conta ainda.\nCadastre suas contas bancárias, carteira e investimentos.',
        action: FilledButton.icon(
          onPressed: () => AccountForm.open(context),
          icon: const Icon(Icons.add),
          label: const Text('Nova conta'),
        ),
      );
    } else {
      final total = active.fold<int>(0, (s, a) => s + a.balance);
      final projected = active.fold<int>(0, (s, a) => s + a.projectedMonthEnd);
      body = RefreshIndicator(
        onRefresh: catalog.refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            StitchedCard(
              child: Padding(
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Saldo atual', style: muted),
                          HeroAmount(total, fontSize: 24),
                          Text('só o que já foi pago', style: muted),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Previsto no fim do mês', style: muted),
                          HeroAmount(projected, fontSize: 24),
                          Text('pagos + pendentes', style: muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final a in active) _AccountTile(account: a),
            if (archived.isNotEmpty)
              ExpansionTile(
                title: Text('Arquivadas (${archived.length})'),
                children: [for (final a in archived) _AccountTile(account: a)],
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas'),
        actions: [
          IconButton(
            tooltip: 'Categorias',
            icon: const Icon(Icons.label_outline),
            onPressed: () => CategoriesScreen.open(context),
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        heroTag: null, // várias abas com "+" na mesma rota
        tooltip: 'Nova conta',
        onPressed: () => AccountForm.open(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: IconBadge(icon: accountIcon(account.type), color: hexColor(account.color)),
      title: Text(account.name),
      subtitle: Text('${accountTypes[account.type] ?? ''} · previsto ${money(account.projectedMonthEnd)}'),
      trailing: Amount(account.balance, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      onTap: () => AccountForm.open(context, existing: account),
    );
  }
}

class AccountForm extends StatefulWidget {
  const AccountForm({super.key, this.existing});

  final Account? existing;

  static Future<bool?> open(BuildContext context, {Account? existing}) => Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => AccountForm(existing: existing)));

  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _initial = TextEditingController(
    text: widget.existing == null ? '' : centsToText(widget.existing!.initialBalance),
  );
  late String _type = widget.existing?.type ?? 'CHECKING';
  late bool _negative = (widget.existing?.initialBalance ?? 0) < 0;
  late String? _color = widget.existing?.color ?? swatches.first;
  late bool _archived = widget.existing?.archived ?? false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _initial.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<Session>().api;
    final catalog = context.read<Catalog>();
    final cents = textToCents(_initial.text) * (_negative ? -1 : 1);
    final body = {
      'name': _name.text.trim(),
      'type': _type,
      'initialBalance': cents,
      'color': _color,
      if (_isEdit) 'archived': _archived,
    };
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await api.put('/accounts/${widget.existing!.id}', body);
      } else {
        await api.post('/accounts', body);
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
      title: 'Excluir conta',
      message:
          'A conta "${widget.existing!.name}" e TODOS os lançamentos dela serão excluídos. '
          'Se quiser só esconder, use "Arquivada".',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await api.delete('/accounts/${widget.existing!.id}');
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar conta' : 'Nova conta'),
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
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Nubank, Itaú, Carteira'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: [
                for (final e in accountTypes.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Row(children: [Icon(accountIcon(e.key), size: 18), const SizedBox(width: 8), Text(e.value)]),
                  ),
              ],
              decoration: const InputDecoration(labelText: 'Tipo'),
              onChanged: (v) => setState(() => _type = v ?? 'CHECKING'),
            ),
            const SizedBox(height: 16),
            MoneyField(
              controller: _initial,
              label: 'Saldo inicial',
              allowNegative: true,
              negative: _negative,
              onToggleNegative: () => setState(() => _negative = !_negative),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(
                'Quanto havia na conta antes do primeiro lançamento registrado no app.',
                style: theme.textTheme.bodySmall,
              ),
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
                title: const Text('Arquivada'),
                subtitle: const Text('Some das listas, mas o histórico continua nos relatórios'),
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
