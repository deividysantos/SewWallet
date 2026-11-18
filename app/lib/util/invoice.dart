import 'dart:math';

import '../models/ledger.dart';

int _clampDay(int y, int m, int d) => min(d, DateTime(y, m + 1, 0).day);

/// Vencimento da fatura em que entra uma compra feita em [date]
/// (mesma regra da API: conta o dia de fechamento do cartão).
DateTime invoiceDueFor(DateTime date, CardInfo card) {
  final closing = _clampDay(date.year, date.month, card.closingDay);
  final next = date.day > closing || (card.closingDayInNext && date.day == closing);
  final ref = DateTime(date.year, date.month + (next ? 1 : 0), 1);
  final due = DateTime(ref.year, ref.month + (card.dueDay > card.closingDay ? 0 : 1), 1);
  return DateTime(due.year, due.month, _clampDay(due.year, due.month, card.dueDay));
}
