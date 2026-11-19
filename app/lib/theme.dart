import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Identidade "Ateliê": ver docs/identidade-visual.md.

/// Paleta do SewWallet (claro = Linho, escuro = Feltro).
abstract final class SewPalette {
  // Claro
  static const linho = Color(0xFFF4EEE3);
  static const papel = Color(0xFFFFFBF4);
  static const algodao = Color(0xFFECE4D5);
  static const algodaoEscuro = Color(0xFFE3D9C7);
  static const tinta = Color(0xFF1F2C38);
  static const tintaSuave = Color(0xFF5F5A50);
  static const cobre = Color(0xFFB8612A);
  static const petroleo = Color(0xFF2E6A6E);
  static const musgo = Color(0xFF3A7449);
  static const tijolo = Color(0xFFAE4029);
  static const mostarda = Color(0xFFA8740F);
  static const giz = Color(0xFFDDD2BF);
  static const gizForte = Color(0xFFC3B59D);

  // Escuro
  static const feltro = Color(0xFF14181C);
  static const feltroSup = Color(0xFF1B2025);
  static const feltroSup2 = Color(0xFF252B31);
  static const feltroSup3 = Color(0xFF2E353C);
  static const linhoTexto = Color(0xFFEDE5D6);
  static const linhoSuave = Color(0xFFA9A193);
  static const cobreClaro = Color(0xFFE3A06A);
  static const petroleoClaro = Color(0xFF7FB7B9);
  static const musgoClaro = Color(0xFF8CC69A);
  static const tijoloClaro = Color(0xFFEE8D77);
  static const mostardaClara = Color(0xFFE4B75C);
  static const gizEscuro = Color(0xFF343B42);
  static const gizEscuroForte = Color(0xFF4A535C);
}

/// Fontes: Fraunces (títulos), DM Sans (interface), IBM Plex Mono (valores).
abstract final class SewFonts {
  /// Desligado nos testes (lá não há rede para baixar as fontes).
  static bool enabled = true;

  static TextStyle display([TextStyle? base]) =>
      enabled ? GoogleFonts.fraunces(textStyle: base) : (base ?? const TextStyle());

  static TextStyle body([TextStyle? base]) =>
      enabled ? GoogleFonts.dmSans(textStyle: base) : (base ?? const TextStyle());

  static TextStyle mono([TextStyle? base]) {
    final s = enabled ? GoogleFonts.ibmPlexMono(textStyle: base) : (base ?? const TextStyle());
    return s.copyWith(fontFeatures: const [FontFeature.tabularFigures()], letterSpacing: -0.2);
  }
}

/// Cores financeiras (receita/despesa) e da costura, que acompanham o tema claro/escuro.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.income,
    required this.expense,
    required this.warning,
    required this.stitch,
    required this.accent,
  });

  final Color income;
  final Color expense;
  final Color warning;

  /// Cor do pesponto (linha tracejada).
  final Color stitch;

  /// Cobre: hoje, seleção, botão +.
  final Color accent;

  static FinanceColors of(BuildContext context) => Theme.of(context).extension<FinanceColors>()!;

  @override
  FinanceColors copyWith({Color? income, Color? expense, Color? warning, Color? stitch, Color? accent}) =>
      FinanceColors(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        warning: warning ?? this.warning,
        stitch: stitch ?? this.stitch,
        accent: accent ?? this.accent,
      );

  @override
  FinanceColors lerp(FinanceColors? other, double t) => other == null
      ? this
      : FinanceColors(
          income: Color.lerp(income, other.income, t)!,
          expense: Color.lerp(expense, other.expense, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          stitch: Color.lerp(stitch, other.stitch, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
        );
}

ColorScheme _scheme(bool dark) => dark
    ? const ColorScheme(
        brightness: Brightness.dark,
        primary: SewPalette.cobreClaro,
        onPrimary: Color(0xFF2B1608),
        primaryContainer: Color(0xFF4A2E1A),
        onPrimaryContainer: Color(0xFFF6D9C2),
        secondary: SewPalette.cobreClaro,
        onSecondary: Color(0xFF2B1608),
        secondaryContainer: Color(0xFF3A2A1E),
        onSecondaryContainer: Color(0xFFF3DCC8),
        tertiary: SewPalette.petroleoClaro,
        onTertiary: Color(0xFF0E2A2B),
        tertiaryContainer: Color(0xFF1F3D3F),
        onTertiaryContainer: Color(0xFFCDE8E9),
        error: SewPalette.tijoloClaro,
        onError: Color(0xFF3A0E05),
        errorContainer: Color(0xFF5A2418),
        onErrorContainer: Color(0xFFFBD8CF),
        surface: SewPalette.feltro,
        onSurface: SewPalette.linhoTexto,
        onSurfaceVariant: SewPalette.linhoSuave,
        surfaceContainerLowest: Color(0xFF101316),
        surfaceContainerLow: SewPalette.feltroSup,
        surfaceContainer: SewPalette.feltroSup,
        surfaceContainerHigh: SewPalette.feltroSup2,
        surfaceContainerHighest: SewPalette.feltroSup3,
        outline: SewPalette.gizEscuroForte,
        outlineVariant: SewPalette.gizEscuro,
        inverseSurface: SewPalette.linhoTexto,
        onInverseSurface: SewPalette.feltro,
        inversePrimary: SewPalette.cobre,
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint: Colors.transparent,
      )
    : const ColorScheme(
        brightness: Brightness.light,
        primary: SewPalette.tinta,
        onPrimary: SewPalette.linho,
        primaryContainer: Color(0xFFDCE3E8),
        onPrimaryContainer: SewPalette.tinta,
        secondary: SewPalette.cobre,
        onSecondary: Color(0xFFFFF6EE),
        secondaryContainer: Color(0xFFF3DFCC),
        onSecondaryContainer: Color(0xFF4A230A),
        tertiary: SewPalette.petroleo,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFD3E6E5),
        onTertiaryContainer: Color(0xFF123536),
        error: SewPalette.tijolo,
        onError: Colors.white,
        errorContainer: Color(0xFFF6D9CF),
        onErrorContainer: Color(0xFF4A140A),
        surface: SewPalette.linho,
        onSurface: SewPalette.tinta,
        onSurfaceVariant: SewPalette.tintaSuave,
        surfaceContainerLowest: SewPalette.papel,
        surfaceContainerLow: SewPalette.papel,
        surfaceContainer: Color(0xFFF8F3EA),
        surfaceContainerHigh: SewPalette.algodao,
        surfaceContainerHighest: SewPalette.algodaoEscuro,
        outline: SewPalette.gizForte,
        outlineVariant: SewPalette.giz,
        inverseSurface: SewPalette.tinta,
        onInverseSurface: SewPalette.linho,
        inversePrimary: SewPalette.cobreClaro,
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint: Colors.transparent,
      );

TextTheme _textTheme(TextTheme base, Color ink) {
  TextStyle? d(TextStyle? s, {FontWeight w = FontWeight.w600, double ls = -0.3}) =>
      s == null ? null : SewFonts.display(s.copyWith(fontWeight: w, letterSpacing: ls, color: ink));
  TextStyle? b(TextStyle? s, {FontWeight? w, double? ls}) =>
      s == null ? null : SewFonts.body(s.copyWith(fontWeight: w, letterSpacing: ls, color: s.color ?? ink));

  return base.copyWith(
    displayLarge: d(base.displayLarge),
    displayMedium: d(base.displayMedium),
    displaySmall: d(base.displaySmall),
    headlineLarge: d(base.headlineLarge),
    headlineMedium: d(base.headlineMedium),
    headlineSmall: d(base.headlineSmall),
    titleLarge: d(base.titleLarge, ls: -0.2),
    titleMedium: b(base.titleMedium, w: FontWeight.w600, ls: 0),
    titleSmall: b(base.titleSmall, w: FontWeight.w600, ls: 0),
    bodyLarge: b(base.bodyLarge, ls: 0),
    bodyMedium: b(base.bodyMedium, ls: 0),
    bodySmall: b(base.bodySmall, ls: 0.1),
    labelLarge: b(base.labelLarge, w: FontWeight.w600, ls: 0.2),
    labelMedium: b(base.labelMedium, w: FontWeight.w500, ls: 0.2),
    labelSmall: b(base.labelSmall, w: FontWeight.w500, ls: 0.3),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = _scheme(dark);
  final accent = dark ? SewPalette.cobreClaro : SewPalette.cobre;
  final card = dark ? SewPalette.feltroSup : SewPalette.papel;
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final text = _textTheme(base.textTheme, scheme.onSurface);

  RoundedRectangleBorder r(double radius, [BorderSide side = BorderSide.none]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);
  final hairline = BorderSide(color: scheme.outlineVariant);

  OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: w),
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: text,
    primaryTextTheme: text,
    dividerColor: scheme.outlineVariant,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      titleTextStyle: SewFonts.display(
        TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: scheme.onSurface),
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: r(14, hairline),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: r(12), minimumSize: const Size(64, 46), textStyle: text.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: r(12),
        minimumSize: const Size(64, 44),
        side: BorderSide(color: scheme.outline),
        foregroundColor: scheme.onSurface,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: r(10),
        foregroundColor: dark ? accent : scheme.primary,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: r(10))),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(r(10)),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? (dark ? accent : SewPalette.tinta) : card,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: dark ? const Color(0xFF2B1608) : const Color(0xFFFFF6EE),
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: r(18),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 66,
      indicatorColor: accent.withValues(alpha: dark ? 0.22 : 0.16),
      indicatorShape: r(10),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelSmall?.copyWith(
          // 5 abas: "Lançamentos" precisa caber em uma linha num celular de 360 px.
          fontSize: 11,
          letterSpacing: 0,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 22,
          color: s.contains(WidgetState.selected) ? (dark ? accent : SewPalette.cobre) : scheme.onSurfaceVariant,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: inputBorder(scheme.outline),
      enabledBorder: inputBorder(scheme.outline),
      focusedBorder: inputBorder(accent, 1.6),
      errorBorder: inputBorder(scheme.error),
      focusedErrorBorder: inputBorder(scheme.error, 1.6),
      disabledBorder: inputBorder(scheme.outlineVariant),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (s) => (text.bodyMedium ?? const TextStyle()).copyWith(
          color: s.contains(WidgetState.error)
              ? scheme.error
              : s.contains(WidgetState.focused)
              ? accent
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    chipTheme: ChipThemeData(shape: r(8, hairline), backgroundColor: card, labelStyle: text.labelMedium),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: r(18),
      titleTextStyle: text.headlineSmall?.copyWith(fontSize: 22),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: r(12, hairline),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      shape: r(12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent, linearTrackColor: Colors.transparent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? (dark ? const Color(0xFF2B1608) : SewPalette.papel) : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : scheme.surfaceContainerHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : scheme.outline,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? (dark ? accent : SewPalette.tinta) : Colors.transparent,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : scheme.outline),
    ),
    badgeTheme: BadgeThemeData(backgroundColor: accent, textColor: scheme.onSecondary),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(8)),
      textStyle: text.labelSmall?.copyWith(color: scheme.onInverseSurface),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: dark ? SewPalette.feltroSup2 : SewPalette.tinta,
      headerForegroundColor: dark ? SewPalette.linhoTexto : SewPalette.linho,
      shape: r(18),
    ),
    extensions: [
      FinanceColors(
        income: dark ? SewPalette.musgoClaro : SewPalette.musgo,
        expense: dark ? SewPalette.tijoloClaro : SewPalette.tijolo,
        warning: dark ? SewPalette.mostardaClara : SewPalette.mostarda,
        stitch: accent.withValues(alpha: dark ? 0.55 : 0.5),
        accent: accent,
      ),
    ],
  );
}

/// No navegador (tela larga), mostra o app com largura de celular, centralizado sobre o "tecido".
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
            border: Border.symmetric(vertical: BorderSide(color: scheme.outline)),
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
