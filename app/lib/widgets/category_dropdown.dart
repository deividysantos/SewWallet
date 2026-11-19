import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../screens/categories_screen.dart';
import '../state/catalog.dart';
import '../util/format.dart';

/// Campo de categoria: abre uma folha com busca e as categorias em grade (ícone + cor), mais
/// "Sem categoria" e "Nova categoria…" (cria por cima da tela atual, sem perder o que já foi
/// preenchido, e já seleciona).
class CategoryDropdown extends StatelessWidget {
  const CategoryDropdown({
    super.key,
    required this.income,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.dense = false,
  });

  /// Categorias de receita (true) ou de despesa (false).
  final bool income;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final bool dense;

  Future<void> _pick(BuildContext context) async {
    final result = await showModalBottomSheet<_Pick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _CategorySheet(income: income, selected: value),
    );
    if (result == null || !context.mounted) return;
    if (result.createNew) {
      final id = await CategoryForm.create(context, income: income);
      if (id != null) onChanged(id);
    } else {
      onChanged(result.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<Catalog>();
    final cat = catalog.categories.where((c) => c.id == value && c.isIncome == income).firstOrNull;
    final theme = Theme.of(context);
    return InkWell(
      key: const ValueKey('categoryField'),
      borderRadius: BorderRadius.circular(4),
      onTap: enabled ? () => _pick(context) : null,
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: 'Categoria',
          isDense: dense,
          enabled: enabled,
          suffixIcon: const Icon(Icons.expand_more),
        ),
        child: Row(
          children: [
            if (cat != null) ...[
              CircleAvatar(
                radius: dense ? 9 : 11,
                backgroundColor: (hexColor(cat.color) ?? theme.colorScheme.primary).withValues(alpha: 0.18),
                child: Icon(
                  categoryIcon(cat.icon),
                  size: dense ? 12 : 14,
                  color: hexColor(cat.color) ?? theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                cat?.name ?? 'Sem categoria',
                overflow: TextOverflow.ellipsis,
                style: cat == null ? TextStyle(color: theme.colorScheme.onSurfaceVariant) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pick {
  const _Pick(this.id, {this.createNew = false});
  final String? id;
  final bool createNew;
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.income, required this.selected});
  final bool income;
  final String? selected;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String _query = '';

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = context.watch<Catalog>().categories.where((c) => c.isIncome == widget.income).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final q = _norm(_query.trim());
    final list = q.isEmpty ? all : all.where((c) => _norm(c.name).contains(q)).toList();

    Widget tile(Category? c) {
      final selected = (c?.id) == widget.selected;
      final color = c == null ? scheme.outline : (hexColor(c.color) ?? scheme.primary);
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pop(context, _Pick(c?.id)),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : null,
            border: Border.all(color: selected ? color : scheme.outlineVariant, width: selected ? 1.6 : 1),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.16),
                child: Icon(c == null ? Icons.block : categoryIcon(c.icon), color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                c?.name ?? 'Sem categoria',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: selected ? FontWeight.w700 : null),
              ),
            ],
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.income ? 'Categoria da receita' : 'Categoria da despesa',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, const _Pick(null, createNew: true)),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nova categoria…'),
                  ),
                ],
              ),
            ),
            if (all.length > 8)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Buscar categoria',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            Expanded(
              child: GridView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 112,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  // Altura fixa: ícone + até 2 linhas de nome, em qualquer largura de tela.
                  mainAxisExtent: 112,
                ),
                children: [if (q.isEmpty) tile(null), for (final c in list) tile(c)],
              ),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Nenhuma categoria com "$_query".', textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}
