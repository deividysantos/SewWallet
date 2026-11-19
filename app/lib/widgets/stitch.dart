import 'package:flutter/material.dart';

import '../theme.dart';

const _dash = 6.0;
const _gap = 4.0;
const _stroke = 1.3;

/// Pesponto: linha tracejada horizontal, assinatura visual do app.
class Stitch extends StatelessWidget {
  const Stitch({super.key, this.color, this.indent = 0, this.endIndent = 0});

  final Color? color;
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent, right: endIndent),
      child: SizedBox(
        height: _stroke,
        width: double.infinity,
        child: CustomPaint(painter: _LinePainter(color ?? FinanceColors.of(context).stitch)),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      canvas.drawLine(Offset(x, y), Offset((x + _dash).clamp(0, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.color != color;
}

/// Cartão "costurado": borda fina + pesponto por dentro, como um remendo.
/// Para os cartões de destaque (resumos); os demais usam o [Card] normal.
class StitchedCard extends StatelessWidget {
  const StitchedCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 8),
    this.padding = const EdgeInsets.all(18),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? theme.cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: CustomPaint(
          foregroundPainter: _RectStitchPainter(FinanceColors.of(context).stitch),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _RectStitchPainter extends CustomPainter {
  _RectStitchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 5.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
      const Radius.circular(10),
    );
    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, (d + _dash).clamp(0, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_RectStitchPainter old) => old.color != color;
}

/// Logotipo em texto: *sew* (Fraunces itálico) + wallet, com pesponto embaixo.
class SewMark extends StatelessWidget {
  const SewMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = FinanceColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'sew',
                style: SewFonts.display(
                  TextStyle(
                    fontSize: size,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              TextSpan(
                text: 'wallet',
                style: SewFonts.body(
                  TextStyle(
                    fontSize: size * 0.82,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: size * 4.2,
          child: Stitch(color: colors.accent.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}
