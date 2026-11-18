import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/format.dart';

/// Valor em reais; vermelho se negativo.
class Amount extends StatelessWidget {
  const Amount(this.cents, {super.key, this.style, this.color});

  final int cents;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    return Text(
      money(cents),
      style: (style ?? const TextStyle()).copyWith(
        color: color ?? (cents < 0 ? colors.expense : null),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Círculo com ícone colorido (categoria, conta, cartão).
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.radius = 18});

  final IconData icon;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.withValues(alpha: 0.15),
      child: Icon(icon, size: radius * 1.1, color: c),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Cores sugeridas para contas e cartões.
const swatches = [
  '#820AD1', '#EC7000', '#43A047', '#1E88E5', '#E53935',
  '#00897B', '#FDD835', '#6D4C41', '#546E7A', '#D81B60',
];

class ColorChoice extends StatelessWidget {
  const ColorChoice({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final hex in swatches)
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onChanged(hex),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hexColor(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: value == hex ? scheme.onSurface : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
