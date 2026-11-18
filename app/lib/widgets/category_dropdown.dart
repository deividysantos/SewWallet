import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/categories_screen.dart';
import '../state/catalog.dart';
import '../util/format.dart';

/// Escolha de categoria com a opção "Nova categoria…" no fim da lista: cria a
/// categoria por cima da tela atual (sem perder o que já foi preenchido) e já a seleciona.
class CategoryDropdown extends StatefulWidget {
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

  @override
  State<CategoryDropdown> createState() => _CategoryDropdownState();
}

class _CategoryDropdownState extends State<CategoryDropdown> {
  static const _newValue = '__new_category__';

  /// Força o campo a recriar o estado interno (ao cancelar a criação, volta ao valor anterior).
  int _generation = 0;

  Future<void> _createNew() async {
    setState(() => _generation++);
    final id = await CategoryForm.create(context, income: widget.income);
    if (!mounted) return;
    if (id != null) widget.onChanged(id);
    setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<Catalog>().categories.where((c) => c.isIncome == widget.income).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final value = categories.any((c) => c.id == widget.value) ? widget.value : null;
    final primary = Theme.of(context).colorScheme.primary;

    return DropdownButtonFormField<String?>(
      key: ValueKey('cat-${widget.income}-$value-$_generation'),
      initialValue: value,
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
        DropdownMenuItem<String?>(
          value: _newValue,
          child: Row(children: [
            Icon(Icons.add, size: 18, color: primary),
            const SizedBox(width: 8),
            Text('Nova categoria…', style: TextStyle(color: primary)),
          ]),
        ),
      ],
      decoration: InputDecoration(labelText: 'Categoria', isDense: widget.dense),
      onChanged: widget.enabled
          ? (v) {
              if (v == _newValue) {
                _createNew();
              } else {
                widget.onChanged(v);
              }
            }
          : null,
    );
  }
}
