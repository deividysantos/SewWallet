import 'package:flutter/material.dart';

const _seed = Color(0xFF00695C);

/// Cores financeiras (receita/despesa) que acompanham o tema claro/escuro.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({required this.income, required this.expense, required this.warning});

  final Color income;
  final Color expense;
  final Color warning;

  static FinanceColors of(BuildContext context) => Theme.of(context).extension<FinanceColors>()!;

  @override
  FinanceColors copyWith({Color? income, Color? expense, Color? warning}) => FinanceColors(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        warning: warning ?? this.warning,
      );

  @override
  FinanceColors lerp(FinanceColors? other, double t) => other == null
      ? this
      : FinanceColors(
          income: Color.lerp(income, other.income, t)!,
          expense: Color.lerp(expense, other.expense, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    extensions: [
      FinanceColors(
        income: dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
        expense: dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828),
        warning: dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
      ),
    ],
  );
}

/// No navegador (tela larga), mostra o app com largura de celular, centralizado.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  final Widget child;

  static const maxWidth = 440.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= maxWidth + 40) return child;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Container(
          width: maxWidth,
          decoration: BoxDecoration(
            border: Border.symmetric(vertical: BorderSide(color: scheme.outlineVariant)),
          ),
          child: MediaQuery(
            data: media.copyWith(size: Size(maxWidth, media.size.height)),
            child: child,
          ),
        ),
      ),
    );
  }
}
