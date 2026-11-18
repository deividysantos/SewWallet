import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sewwallet/state/catalog.dart';
import 'package:sewwallet/state/session.dart';
import 'package:sewwallet/state/settings.dart';
import 'package:sewwallet/theme.dart';
import 'package:sewwallet/util/format.dart';

/// API falsa: responde com dados fixos e guarda as requisições feitas pelo app.
class FakeApi {
  final requests = <http.Request>[];

  late final http.Client client = MockClient((req) async {
    requests.add(req);
    final key = '${req.method} ${req.url.path}';
    final handler = routes[key];
    if (handler == null) {
      return http.Response.bytes(utf8.encode('{"error":"sem rota $key"}'), 404);
    }
    return http.Response.bytes(utf8.encode(jsonEncode(handler(req))), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });

  List<http.Request> calls(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path).toList();

  Map<String, dynamic> lastBody(String method, String path) =>
      jsonDecode(calls(method, path).last.body) as Map<String, dynamic>;

  static String get today => apiDate(DateTime.now());

  late final Map<String, Object? Function(http.Request)> routes = {
    'GET /accounts': (_) => [
          {'id': 'a1', 'name': 'Nubank', 'type': 'CHECKING', 'initialBalance': 100000, 'balance': 500000, 'projectedMonthEnd': 450000, 'archived': false, 'color': '#820AD1'},
          {'id': 'a2', 'name': 'Itaú', 'type': 'CHECKING', 'initialBalance': 0, 'balance': 200000, 'projectedMonthEnd': 260000, 'archived': false, 'color': '#EC7000'},
        ],
    'GET /cards': (_) => [
          {
            'id': 'c1', 'name': 'Roxinho', 'limit': 800000, 'closingDay': 5, 'dueDay': 12, 'closingDayInNext': true,
            'paymentAccountId': 'a1', 'archived': false, 'color': '#820AD1', 'limitUsed': 120000, 'limitAvailable': 680000,
            'currentInvoice': _invoice,
          },
        ],
    'GET /categories': (_) => [
          {'id': 'k1', 'name': 'Compras', 'kind': 'EXPENSE', 'color': '#AD1457', 'icon': 'shopping_bag'},
          {'id': 'k2', 'name': 'Salário', 'kind': 'INCOME', 'color': '#2E7D32', 'icon': 'payments'},
        ],
    'GET /transactions': (_) => {
          'from': today,
          'to': today,
          'today': today,
          'openingBalance': {'realized': 700000, 'projected': 700000},
          'closingBalance': {'realized': 700000, 'projected': 650000},
          'summary': {'income': 0, 'expense': 50000, 'cardExpense': 12000},
          'days': [
            {
              'date': today,
              'balance': {'realized': 700000, 'projected': 650000},
              'items': [
                {
                  'kind': 'transaction', 'id': 't1', 'type': 'EXPENSE', 'status': 'PENDING', 'description': 'Conta de luz',
                  'amount': 50000, 'date': today, 'overdue': false, 'affectsBalance': true,
                  'account': {'id': 'a1', 'name': 'Nubank'}, 'installment': null,
                },
                {
                  'kind': 'transaction', 'id': 't2', 'type': 'EXPENSE', 'status': 'PAID', 'description': 'Notebook com descrição bem comprida para testar',
                  'amount': 12000, 'date': today, 'overdue': false, 'affectsBalance': false,
                  'card': {'id': 'c1', 'name': 'Roxinho'}, 'invoice': {'id': 'i1', 'refMonth': '2026-12-01', 'dueDate': '2026-12-12'},
                  'installment': {'groupId': 'g', 'number': 2, 'total': 10}, 'recurrenceId': null,
                },
                {
                  'kind': 'invoice', 'id': 'i1', 'description': 'Fatura Roxinho', 'dueDate': today, 'closingDate': today,
                  'card': {'id': 'c1', 'name': 'Roxinho'}, 'account': {'id': 'a1', 'name': 'Nubank'},
                  'total': 50000, 'paid': 10000, 'remaining': 40000, 'status': 'CLOSED',
                },
              ],
            },
          ],
        },
    'GET /cards/c1/invoices': (_) => [_invoice],
    'GET /invoices/i1': (_) => {
          ..._invoice,
          'items': [
            {'id': 't2', 'type': 'EXPENSE', 'status': 'PAID', 'description': 'Notebook', 'amount': 48000, 'date': '2026-11-14', 'installmentNumber': 3, 'installmentTotal': 10, 'category': {'id': 'k1', 'name': 'Compras', 'color': '#AD1457', 'icon': 'shopping_bag'}},
            {'id': 't3', 'type': 'INCOME', 'status': 'PAID', 'description': 'Estorno', 'amount': 2000, 'date': '2026-11-16'},
          ],
          'payments': [],
        },
    'POST /invoices/i1/payments': (_) => {'id': 'p1'},
    'POST /transactions': (_) => {'count': 3, 'transactions': []},
    'PUT /transactions/t1': (_) => {'id': 't1'},
    'PUT /transactions/t2': (_) => {'id': 't2'},
    'DELETE /transactions/t1': (_) => {'deleted': 1},
    'PATCH /transactions/t1/status': (_) => {'id': 't1'},
    'POST /accounts': (_) => {'id': 'a3'},
    'POST /categories': (_) => {'id': 'k3'},
    'PUT /categories/k1': (_) => {'id': 'k1'},
    'DELETE /categories/k1': (_) => null,
    'POST /cards': (_) => {'id': 'c2'},
    'GET /reports/cashflow': (_) => {
          'mode': 'cumulative', 'basis': 'projected', 'granularity': 'month',
          'from': '2026-10-01', 'to': '2026-12-31', 'openingBalance': 100000, 'closingBalance': 250000,
          'totals': {'income': 900000, 'expense': 750000, 'transfersIn': 0, 'transfersOut': 0, 'net': 150000},
          'buckets': [
            {'start': '2026-10-01', 'end': '2026-10-31', 'income': 300000, 'expense': 250000, 'transfersIn': 0, 'transfersOut': 0, 'net': 50000, 'opening': 100000, 'closing': 150000},
            {'start': '2026-11-01', 'end': '2026-11-30', 'income': 300000, 'expense': 350000, 'transfersIn': 0, 'transfersOut': 0, 'net': -50000, 'opening': 150000, 'closing': 100000},
            {'start': '2026-12-01', 'end': '2026-12-31', 'income': 300000, 'expense': 150000, 'transfersIn': 0, 'transfersOut': 0, 'net': 150000, 'opening': 100000, 'closing': 250000},
          ],
        },
  };

  static const _invoice = {
    'id': 'i1', 'refMonth': '2026-12-01', 'closingDate': '2026-12-05', 'dueDate': '2026-12-12',
    'total': 46000, 'paid': 0, 'remaining': 46000, 'status': 'OPEN',
  };
}

/// Monta [home] com tela de celular, sessão logada na API falsa e catálogo carregado.
Future<FakeApi> pumpScreen(WidgetTester tester, Widget home, {FakeApi? api, AppSettings? settings}) async {
  SewFonts.enabled = false; // sem rede nos testes
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final fake = api ?? FakeApi();
  final session = Session(httpClient: fake.client)
    ..token = 'token'
    ..serverUrl = 'http://api';
  final catalog = Catalog(session);
  await catalog.refresh();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: catalog),
        ChangeNotifierProvider.value(value: settings ?? AppSettings()),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

/// Tela vazia com um botão que abre [open] (para testar telas empilhadas).
Widget launcher(void Function(BuildContext) open) => Scaffold(
      body: Builder(builder: (ctx) => Center(child: TextButton(onPressed: () => open(ctx), child: const Text('abrir')))),
    );

Future<void> tapText(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    // Listas só constroem o que está na tela: rola até o texto aparecer.
    await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
  }
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}
