import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sewwallet/models/ledger.dart';
import 'package:sewwallet/util/format.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('lê a resposta de /transactions', () {
    final page = TransactionsPage.fromJson({
      'today': '2026-11-18',
      'openingBalance': {'realized': 1000, 'projected': 1000},
      'closingBalance': {'realized': 800, 'projected': 500},
      'summary': {'income': 0, 'expense': 200, 'cardExpense': 50},
      'days': [
        {
          'date': '2026-11-18',
          'balance': {'realized': 800, 'projected': 500},
          'items': [
            {
              'kind': 'transaction',
              'id': 't1',
              'type': 'EXPENSE',
              'status': 'PENDING',
              'description': 'Conta de água',
              'amount': 300,
              'date': '2026-11-14',
              'overdue': true,
              'affectsBalance': true,
              'account': {'id': 'a', 'name': 'Itaú'},
              'installment': null,
            },
            {
              'kind': 'invoice',
              'id': 'i1',
              'description': 'Fatura Nubank',
              'dueDate': '2026-11-18',
              'closingDate': '2026-11-11',
              'total': 5000,
              'paid': 0,
              'remaining': 5000,
              'status': 'CLOSED',
            },
          ],
        },
      ],
    });

    expect(page.days.single.balance.projected, 500);
    final items = page.days.single.items;
    expect(items[0], isA<TxItem>());
    expect((items[0] as TxItem).overdue, isTrue);
    expect(items[1], isA<InvoiceItem>());
    expect((items[1] as InvoiceItem).status, InvoiceStatus.closed);
  });

  test('formata dinheiro em reais', () {
    expect(money(123456).replaceAll(' ', ' '), r'R$ 1.234,56');
    expect(money(-990).replaceAll(' ', ' '), r'-R$ 9,90');
  });
}
