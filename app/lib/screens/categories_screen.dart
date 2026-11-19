import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Categorias de despesa e receita.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen()));

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  bool _income = false;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<Catalog>();
    final list = catalog.categories.where((c) => c.isIncome == _income).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Despesas')),
                  ButtonSegment(value: true, label: Text('Receitas')),
                ],
                selected: {_income},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _income = s.first),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyView(
                    icon: Icons.label_outline,
                    message: _income ? 'Nenhuma categoria de receita' : 'Nenhuma categoria de despesa',
                  )
                : RefreshIndicator(
                    onRefresh: catalog.refresh,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 96),
                      children: [
                        for (final c in list)
                          ListTile(
                            leading: IconBadge(icon: categoryIcon(c.icon), color: hexColor(c.color)),
                            title: Text(c.name),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => CategoryForm.open(context, existing: c),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nova categoria',
        onPressed: () => CategoryForm.open(context, income: _income),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CategoryForm extends StatefulWidget {
  const CategoryForm({super.key, this.existing, this.income = false});

  final Category? existing;
  final bool income;

  /// Retorna o id da categoria salva, `true` se excluiu, ou null se cancelou.
  static Future<Object?> open(BuildContext context, {Category? existing, bool income = false}) =>
      Navigator.of(context).push<Object?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CategoryForm(existing: existing, income: income),
        ),
      );

  /// Cria uma categoria sem sair da tela atual; retorna o id dela (null se cancelou).
  static Future<String?> create(BuildContext context, {required bool income}) async {
    final r = await open(context, income: income);
    return r is String ? r : null;
  }

  @override
  State<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<CategoryForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late bool _income = widget.existing?.isIncome ?? widget.income;
  late String? _color = widget.existing?.color ?? swatches.first;
  late String _icon = widget.existing?.icon ?? 'label';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<Session>().api;
    final catalog = context.read<Catalog>();
    final body = {
      'name': _name.text.trim(),
      'color': _color,
      'icon': _icon,
      // O tipo não muda depois de criada (os lançamentos já vinculados dependem dele).
      if (!_isEdit) 'kind': _income ? 'INCOME' : 'EXPENSE',
    };
    setState(() => _saving = true);
    try {
      String? id = widget.existing?.id;
      if (_isEdit) {
        await api.put('/categories/$id', body);
      } else {
        final created = await api.post('/categories', body);
        if (created is Map) id = created['id'] as String?;
      }
      await catalog.refresh();
      if (mounted) Navigator.pop(context, id ?? true);
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
      title: 'Excluir categoria',
      message:
          'A categoria "${widget.existing!.name}" será excluída. Os lançamentos dela continuam, mas ficam sem categoria.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await api.delete('/categories/${widget.existing!.id}');
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
    final scheme = theme.colorScheme;
    final color = hexColor(_color) ?? scheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar categoria' : 'Nova categoria'),
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
            Center(
              child: IconBadge(icon: categoryIcon(_icon), color: color, radius: 32),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Despesa')),
                ButtonSegment(value: true, label: Text('Receita')),
              ],
              selected: {_income},
              showSelectedIcon: false,
              onSelectionChanged: _isEdit ? null : (s) => setState(() => _income = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: !_isEdit,
              decoration: const InputDecoration(labelText: 'Nome'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 20),
            Text('Cor', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ColorChoice(value: _color, onChanged: (c) => setState(() => _color = c)),
            const SizedBox(height: 20),
            Text('Ícone', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in categoryIconNames)
                  Tooltip(
                    message: name,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _icon = name),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: name == _icon ? color.withValues(alpha: 0.2) : null,
                          border: Border.all(
                            color: name == _icon ? color : scheme.outlineVariant,
                            width: name == _icon ? 2 : 1,
                          ),
                        ),
                        child: Icon(categoryIcon(name), color: name == _icon ? color : scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
              ],
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
