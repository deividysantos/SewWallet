import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _plain = NumberFormat('#,##0.00', 'pt_BR');

/// Texto do campo a partir de centavos: 123456 -> "1.234,56".
String centsToText(int cents) => _plain.format(cents.abs() / 100);

/// Centavos a partir do texto do campo (só os dígitos importam).
int textToCents(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? 0 : int.parse(digits);
}

/// Digitação estilo app de banco: os dígitos entram pela direita (1 -> 0,01; 12 -> 0,12...).
class _CentsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);
    final text = digits.isEmpty ? '' : centsToText(int.parse(digits));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Campo de valor em reais. Com [allowNegative], mostra um botão +/−.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    this.label = 'Valor',
    this.autofocus = false,
    this.allowNegative = false,
    this.negative = false,
    this.onToggleNegative,
    this.validator,
    this.style,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool allowNegative;
  final bool negative;
  final VoidCallback? onToggleNegative;
  final String? Function(int cents)? validator;
  final TextStyle? style;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: [_CentsFormatter()],
      style: style,
      decoration: InputDecoration(
        labelText: label,
        hintText: '0,00',
        prefixText: negative ? '− R\$ ' : 'R\$ ',
        suffixIcon: allowNegative
            ? IconButton(
                tooltip: negative ? 'Tornar positivo' : 'Tornar negativo',
                icon: Icon(negative ? Icons.remove_circle : Icons.add_circle_outline),
                onPressed: onToggleNegative,
              )
            : null,
      ),
      onChanged: onChanged == null ? null : (t) => onChanged!(textToCents(t)),
      validator: validator == null ? null : (t) => validator!(textToCents(t ?? '')),
    );
  }
}
