import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

/// Centavos -> "R$ 1.234,56".
String money(int cents) => _money.format(cents / 100);

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "Qua, 18 de nov."
String dayTitle(DateTime d) => _capitalize(DateFormat("EEE, d 'de' MMM", 'pt_BR').format(d));

/// "Novembro 2026"
String monthTitle(DateTime d) => _capitalize(DateFormat('MMMM yyyy', 'pt_BR').format(d));

/// "18/11"
String shortDate(DateTime d) => DateFormat('dd/MM', 'pt_BR').format(d);

/// Formato da API: AAAA-MM-DD.
String apiDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

Color? hexColor(String? hex) {
  if (hex == null || !hex.startsWith('#') || hex.length != 7) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Nomes de ícone das categorias (vindos da API) -> ícones do Material.
const _icons = <String, IconData>{
  'payments': Icons.payments_outlined,
  'work': Icons.work_outline,
  'trending_up': Icons.trending_up,
  'add_circle': Icons.add_circle_outline,
  'restaurant': Icons.restaurant,
  'shopping_cart': Icons.shopping_cart_outlined,
  'home': Icons.home_outlined,
  'bolt': Icons.bolt,
  'directions_car': Icons.directions_car_outlined,
  'favorite': Icons.favorite_outline,
  'school': Icons.school_outlined,
  'celebration': Icons.celebration_outlined,
  'subscriptions': Icons.subscriptions_outlined,
  'shopping_bag': Icons.shopping_bag_outlined,
  'receipt_long': Icons.receipt_long_outlined,
  'more_horiz': Icons.more_horiz,
  'local_cafe': Icons.local_cafe_outlined,
  'local_gas_station': Icons.local_gas_station_outlined,
  'directions_bus': Icons.directions_bus_outlined,
  'flight': Icons.flight_outlined,
  'pets': Icons.pets_outlined,
  'child_care': Icons.child_care_outlined,
  'fitness_center': Icons.fitness_center_outlined,
  'medical_services': Icons.medical_services_outlined,
  'checkroom': Icons.checkroom_outlined,
  'phone_iphone': Icons.phone_iphone_outlined,
  'wifi': Icons.wifi,
  'water_drop': Icons.water_drop_outlined,
  'build': Icons.build_outlined,
  'card_giftcard': Icons.card_giftcard_outlined,
  'sports_esports': Icons.sports_esports_outlined,
  'movie': Icons.movie_outlined,
  'menu_book': Icons.menu_book_outlined,
  'savings': Icons.savings_outlined,
  'account_balance': Icons.account_balance_outlined,
  'volunteer_activism': Icons.volunteer_activism_outlined,
  'sell': Icons.sell_outlined,
  'label': Icons.label_outline,
};

IconData categoryIcon(String? name) => _icons[name] ?? Icons.label_outline;

/// Nomes de ícone disponíveis para categorias (na ordem de exibição).
List<String> get categoryIconNames => _icons.keys.toList();
