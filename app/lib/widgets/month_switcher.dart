import 'package:flutter/material.dart';

import '../util/format.dart';

/// ‹ Mês › : as setas andam um mês; tocar no título volta ao mês atual.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged});

  /// Primeiro dia do mês exibido.
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  static DateTime current() => DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Mês anterior',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: TextButton(
            onPressed: () => onChanged(current()),
            child: Text(monthTitle(month), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
          ),
        ),
        IconButton(
          tooltip: 'Próximo mês',
          onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
