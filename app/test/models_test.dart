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

  test('lê previsões e o vínculo de abatimento', () {
    final f = TxItem.fromJson({
      'kind': 'transaction',
      'id': 'f1',
      'type': 'EXPENSE',
      'status': 'PENDING',
      'description': 'Gasolina',
      'amount': 10000,
      'date': '2026-11-20',
      'forecast': {'state': 'EXPIRED', 'planned': 10000, 'abated': 7000, 'remaining': 3000, 'effective': 0},
    });
    expect(f.isForecast, isTrue);
    expect(f.forecast!.state, ForecastState.expired);
    expect(f.forecast!.remaining, 3000);
    expect(forecastLabel(f.forecast!), 'Previsão expirada');

    final real = TxItem.fromJson({
      'kind': 'transaction',
      'id': 't1',
      'type': 'EXPENSE',
      'status': 'PAID',
      'description': 'Posto',
      'amount': 7000,
      'date': '2026-11-05',
      'forecast': null,
      'forecastId': 'f1',
    });
    expect(real.isForecast, isFalse);
    expect(real.forecastId, 'f1');

    final inv = InvoiceItem.fromJson({
      'kind': 'invoice',
      'id': 'i1',
      'description': 'Fatura',
      'dueDate': '2026-12-12',
      'closingDate': '2026-12-05',
      'total': 5000,
      'paid': 0,
      'remaining': 5000,
      'status': 'OPEN',
      'forecastTotal': 2000,
    });
    expect(inv.forecastTotal, 2000);
  });

  test('lê o vínculo de contrapartida', () {
    Map<String, dynamic> tx(String id, Object? cp) => {
      'kind': 'transaction',
      'id': id,
      'type': 'EXPENSE',
      'status': 'PAID',
      'description': 'x',
      'amount': 100,
      'date': '2026-11-19',
      'counterpart': cp,
    };
    final origin = TxItem.fromJson(tx('o', {'id': 'c', 'role': 'origin'}));
    expect(origin.hasCounterpart, isTrue);
    expect(origin.isCounterpart, isFalse);
    final cp = TxItem.fromJson(tx('c', {'id': 'o', 'role': 'counterpart'}));
    expect(cp.isCounterpart, isTrue);
    expect(cp.hasCounterpart, isFalse);
    expect(cp.counterpartId, 'o');
    expect(TxItem.fromJson(tx('s', null)).counterpartId, isNull);
  });

  test('formata dinheiro em reais', () {
    expect(money(123456).replaceAll(' ', ' '), r'R$ 1.234,56');
    expect(money(-990).replaceAll(' ', ' '), r'-R$ 9,90');
  });
}
