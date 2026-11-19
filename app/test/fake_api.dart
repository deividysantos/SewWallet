import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Resposta de GET /report-filters (filtros preferidos salvos).
  List<Map<String, dynamic>> preferred = [];

  /// Sugestões pendentes (notificações dos bancos) informadas ao Início.
  int suggestionCount = 0;

  static const suggestion = {
    'id': 's1',
    'status': 'PENDING',
    'reason': null,
    'app': 'com.nu.production',
    'appName': 'Nubank',
    'title': 'Compra aprovada',
    'text': 'Compra de R\$ 87,40 APROVADA em POSTO SHELL para o cartão com final 4821.',
    'postedAt': '2026-11-19T21:42:10.000Z',
    'type': 'EXPENSE',
    'channel': 'CARD',
    'amount': 8740,
    'date': '2026-11-19',
    'merchant': 'POSTO SHELL',
    'description': 'Posto Shell',
    'accountId': null,
    'cardId': 'c1',
    'categoryId': 'k1',
    'installments': null,
    'confidence': 0.9,
    'transaction': null,
  };

  late final http.Client client = MockClient((req) async {
    requests.add(req);
    final key = '${req.method} ${req.url.path}';
    final handler = routes[key];
    if (handler == null) {
      return http.Response.bytes(utf8.encode('{"error":"sem rota $key"}'), 404);
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(handler(req))),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  List<http.Request> calls(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path).toList();

  Map<String, dynamic> lastBody(String method, String path) =>
      jsonDecode(calls(method, path).last.body) as Map<String, dynamic>;

  static String get today => apiDate(DateTime.now());

  late final Map<String, Object? Function(http.Request)> routes = {
    'GET /accounts': (_) => [
      {
        'id': 'a1',
        'name': 'Nubank',
        'type': 'CHECKING',
        'initialBalance': 100000,
        'balance': 500000,
        'projectedMonthEnd': 450000,
        'archived': false,
        'color': '#820AD1',
      },
      {
        'id': 'a2',
        'name': 'Itaú',
        'type': 'CHECKING',
        'initialBalance': 0,
        'balance': 200000,
        'projectedMonthEnd': 260000,
        'archived': false,
        'color': '#EC7000',
      },
    ],
    'GET /cards': (_) => [
      {
        'id': 'c1',
        'name': 'Roxinho',
        'limit': 800000,
        'closingDay': 5,
        'dueDay': 12,
        'closingDayInNext': true,
        'paymentAccountId': 'a1',
        'archived': false,
        'color': '#820AD1',
        'limitUsed': 120000,
        'limitAvailable': 680000,
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
              'kind': 'transaction',
              'id': 't1',
              'type': 'EXPENSE',
              'status': 'PENDING',
              'description': 'Conta de luz',
              'amount': 50000,
              'date': today,
              'overdue': false,
              'affectsBalance': true,
              'account': {'id': 'a1', 'name': 'Nubank'},
              'installment': null,
            },
            {
              'kind': 'transaction',
              'id': 't2',
              'type': 'EXPENSE',
              'status': 'PAID',
              'description': 'Notebook com descrição bem comprida para testar',
              'amount': 12000,
              'date': today,
              'overdue': false,
              'affectsBalance': false,
              'card': {'id': 'c1', 'name': 'Roxinho'},
              'invoice': {'id': 'i1', 'refMonth': '2026-12-01', 'dueDate': '2026-12-12'},
              'installment': {'groupId': 'g', 'number': 2, 'total': 10},
              'recurrenceId': null,
            },
            {
              'kind': 'invoice',
              'id': 'i1',
              'description': 'Fatura Roxinho',
              'dueDate': today,
              'closingDate': today,
              'card': {'id': 'c1', 'name': 'Roxinho'},
              'account': {'id': 'a1', 'name': 'Nubank'},
              'total': 50000,
              'paid': 10000,
              'remaining': 40000,
              'status': 'CLOSED',
            },
          ],
        },
      ],
    },
    'GET /cards/c1/invoices': (_) => [_invoice],
    'GET /invoices/i1': (_) => {
      ..._invoice,
      'items': [
        {
          'id': 't2',
          'type': 'EXPENSE',
          'status': 'PAID',
          'description': 'Notebook',
          'amount': 48000,
          'date': '2026-11-14',
          'installmentNumber': 3,
          'installmentTotal': 10,
          'category': {'id': 'k1', 'name': 'Compras', 'color': '#AD1457', 'icon': 'shopping_bag'},
        },
        {
          'id': 't3',
          'type': 'INCOME',
          'status': 'PAID',
          'description': 'Estorno',
          'amount': 2000,
          'date': '2026-11-16',
        },
      ],
      'payments': [],
      'forecasts': [
        {
          ..._forecast,
          'id': 'f9',
          'description': 'Gasolina no cartão',
          'account': null,
          'card': {'id': 'c1', 'name': 'Roxinho'},
          'date': '2026-11-30',
          'forecast': {'state': 'OPEN', 'planned': 10000, 'abated': 0, 'remaining': 10000, 'effective': 10000},
        },
      ],
    },
    'POST /invoices/i1/payments': (_) => {'id': 'p1'},
    'GET /transactions/t2': (_) => {
      'kind': 'transaction',
      'id': 't2',
      'type': 'EXPENSE',
      'status': 'PAID',
      'description': 'Notebook',
      'amount': 48000,
      'date': '2026-11-14',
      'overdue': false,
      'affectsBalance': false,
      'card': {'id': 'c1', 'name': 'Roxinho'},
      'invoice': {'id': 'i1', 'refMonth': '2026-12-01', 'dueDate': '2026-12-12'},
      'installment': {'groupId': 'g', 'number': 3, 'total': 10},
      'recurrenceId': null,
    },
    'POST /transactions': (_) => {
      'count': 3,
      'transactions': [
        {'id': 'tNew'},
      ],
    },
    'PUT /transactions/t1': (_) => {'id': 't1'},
    'PUT /transactions/t2': (_) => {'id': 't2'},
    'DELETE /transactions/t1': (_) => {'deleted': 1},
    'PATCH /transactions/t1/status': (_) => {'id': 't1'},
    'POST /accounts': (_) => {'id': 'a3'},
    'POST /categories': (_) => {'id': 'k3'},
    'PUT /categories/k1': (_) => {'id': 'k1'},
    'DELETE /categories/k1': (_) => null,
    'POST /cards': (_) => {'id': 'c2'},
    'GET /reports/categories': (_) => {
      'kind': 'EXPENSE',
      'from': '2026-11-01',
      'to': '2026-11-30',
      'previousFrom': '2026-10-01',
      'previousTo': '2026-10-31',
      'total': 100000,
      'count': 12,
      'previousTotal': 80000,
      'averageTotal': 90000,
      'categories': [
        {
          'id': 'k1',
          'name': 'Compras',
          'color': '#AD1457',
          'icon': 'shopping_bag',
          'total': 60000,
          'count': 4,
          'share': 0.6,
          'previous': 40000,
          'average': 45000,
        },
        {
          'id': null,
          'name': 'Sem categoria',
          'color': null,
          'icon': null,
          'total': 40000,
          'count': 8,
          'share': 0.4,
          'previous': 40000,
          'average': 45000,
        },
      ],
      'history': [
        {'month': '2026-06-01', 'total': 0},
        {'month': '2026-07-01', 'total': 70000},
        {'month': '2026-08-01', 'total': 90000},
        {'month': '2026-09-01', 'total': 100000},
        {'month': '2026-10-01', 'total': 80000},
        {'month': '2026-11-01', 'total': 100000},
      ],
    },
    'GET /reports/categories/detail': (_) => {
      'categoryId': 'k1',
      'from': '2026-11-01',
      'to': '2026-11-30',
      'total': 58000,
      'history': [
        {'month': '2026-10-01', 'total': 40000},
        {'month': '2026-11-01', 'total': 58000},
      ],
      'items': [
        {
          'kind': 'transaction',
          'id': 't2',
          'type': 'EXPENSE',
          'status': 'PAID',
          'description': 'Notebook',
          'amount': 60000,
          'date': '2026-11-14',
          'overdue': false,
          'affectsBalance': false,
          'card': {'id': 'c1', 'name': 'Roxinho'},
          'installment': null,
          'reportDate': '2026-11-14',
          'reportAmount': 60000,
        },
        {
          'kind': 'transaction',
          'id': 't3',
          'type': 'INCOME',
          'status': 'PAID',
          'description': 'Estorno loja',
          'amount': 2000,
          'date': '2026-11-16',
          'overdue': false,
          'affectsBalance': false,
          'card': {'id': 'c1', 'name': 'Roxinho'},
          'installment': null,
          'reportDate': '2026-11-16',
          'reportAmount': -2000,
        },
      ],
    },
    'GET /transactions/forecasts/open': (_) => [_forecast],
    'PATCH /transactions/f1/forecast-state': (_) => {'id': 'f1'},
    'GET /reports/forecasts': (_) => {
      'from': '2026-11-01',
      'to': '2026-11-30',
      'today': today,
      'totals': {
        'EXPENSE': {'planned': 30000, 'abated': 7000, 'remaining': 23000, 'effective': 23000, 'count': 2},
        'INCOME': {'planned': 0, 'abated': 0, 'remaining': 0, 'effective': 0, 'count': 0},
      },
      'items': [
        {
          ..._forecast,
          'fixed': false,
          'abatements': [
            {
              'kind': 'transaction',
              'id': 't9',
              'type': 'EXPENSE',
              'status': 'PAID',
              'description': 'Posto Shell',
              'amount': 7000,
              'date': '2026-11-05',
              'overdue': false,
              'affectsBalance': true,
              'account': {'id': 'a1', 'name': 'Nubank'},
              'forecastId': 'f1',
            },
          ],
        },
        {
          ..._forecast,
          'id': 'f2',
          'description': 'Mercado',
          'recurrenceId': 'r1',
          'fixed': true,
          'amount': 20000,
          'forecast': {'state': 'OPEN', 'planned': 20000, 'abated': 0, 'remaining': 20000, 'effective': 20000},
          'abatements': [],
        },
      ],
    },
    'GET /report-filters': (_) => preferred,
    'GET /suggestions/count': (_) => {'pending': suggestionCount},
    'GET /suggestions': (req) => req.url.queryParameters['view'] == 'processed'
        ? {
            'aiConfigured': true,
            'items': [
              {
                ...suggestion,
                'id': 's2',
                'status': 'AUTO_PAID',
                'description': 'Conta de luz',
                'amount': 31258,
                'cardId': null,
                'accountId': 'a2',
                'channel': 'DEBIT',
                'categoryId': null,
                'text': 'Pagamento de boleto de R\$ 312,58 realizado - ENEL.',
                'transaction': {
                  'id': 't7',
                  'description': 'Conta de luz',
                  'date': '2026-11-22',
                  'amount': 31258,
                  'status': 'PAID',
                },
              },
            ],
          }
        : {
            'aiConfigured': true,
            'items': [suggestion],
          },
    'POST /suggestions/s1/accept': (_) => {...suggestion, 'status': 'ACCEPTED'},
    'POST /suggestions/s1/dismiss': (_) => {...suggestion, 'status': 'DISMISSED'},
    'POST /suggestions/s2/undo': (_) => {...suggestion, 'id': 's2', 'status': 'PENDING'},
    'PUT /cards/c1': (_) => {'id': 'c1'},
    'PUT /report-filters/cashflow': (req) => {'report': 'cashflow', 'params': jsonDecode(req.body)['params']},
    'DELETE /report-filters/cashflow': (_) => null,
    'PUT /report-filters/dashboard': (req) => {'report': 'dashboard', 'params': jsonDecode(req.body)['params']},
    'PATCH /transactions/cp1/status': (_) => {'id': 'cp1'},
    'GET /reports/counterparts': (_) => {
      'from': '2026-11-01',
      'to': '2026-11-30',
      'today': today,
      'totals': {
        'INCOME': {'pending': 10000, 'settled': 5000, 'count': 2},
        'EXPENSE': {'pending': 0, 'settled': 0, 'count': 0},
      },
      'items': [
        {
          'kind': 'transaction',
          'id': 'cp1',
          'type': 'INCOME',
          'status': 'PENDING',
          'description': 'Compensação de: Fone',
          'amount': 10000,
          'date': '2026-11-12',
          'overdue': false,
          'affectsBalance': true,
          'account': {'id': 'a1', 'name': 'Nubank'},
          'counterpart': {'id': 'o1', 'role': 'counterpart'},
          'origin': {
            'kind': 'transaction',
            'id': 'o1',
            'type': 'EXPENSE',
            'status': 'PAID',
            'description': 'Fone para Ana',
            'amount': 10000,
            'date': '2026-11-02',
            'overdue': false,
            'affectsBalance': false,
            'card': {'id': 'c1', 'name': 'Roxinho'},
            'counterpart': {'id': 'cp1', 'role': 'origin'},
          },
        },
        {
          'kind': 'transaction',
          'id': 'cp2',
          'type': 'INCOME',
          'status': 'PAID',
          'description': 'Compensação de: Presente',
          'amount': 5000,
          'date': '2026-11-05',
          'overdue': false,
          'affectsBalance': true,
          'account': {'id': 'a1', 'name': 'Nubank'},
          'counterpart': {'id': 'o2', 'role': 'counterpart'},
          'origin': {
            'kind': 'transaction',
            'id': 'o2',
            'type': 'EXPENSE',
            'status': 'PAID',
            'description': 'Presente da mãe',
            'amount': 5000,
            'date': '2026-11-05',
            'overdue': false,
            'affectsBalance': true,
            'account': {'id': 'a1', 'name': 'Nubank'},
            'counterpart': {'id': 'cp2', 'role': 'origin'},
          },
        },
      ],
    },
    'GET /reports/dashboard': (_) => {
      'from': '2026-11-01',
      'to': '2026-11-30',
      'today': today,
      'balance': {
        'opening': {'realized': 600000, 'projected': 600000},
        'today': {'realized': 700000, 'projected': 650000},
        'monthEnd': {'realized': 700000, 'projected': 640000},
      },
      'income': {'projected': 900000, 'realized': 800000},
      'expense': {'projected': 300000, 'realized': 250000},
      'net': {'projected': 600000, 'realized': 550000},
      'topExpenses': [
        {
          'id': 'k1',
          'name': 'Compras',
          'color': '#AD1457',
          'icon': 'shopping_bag',
          'total': 200000,
          'count': 3,
          'share': 0.66,
          'previous': 0,
          'average': 0,
        },
      ],
      'topIncomes': [],
      'invoices': [
        {
          'id': 'i1',
          'cardId': 'c1',
          'cardName': 'Roxinho',
          'dueDate': '2026-11-12',
          'closingDate': '2026-11-05',
          'total': 46000,
          'paid': 0,
          'remaining': 46000,
          'status': 'CLOSED',
          'forecastTotal': 0,
        },
      ],
      'cards': [
        {'id': 'c1', 'name': 'Roxinho', 'color': '#820AD1', 'limit': 800000, 'limitUsed': 120000},
      ],
      'forecasts': {
        'EXPENSE': {'planned': 30000, 'abated': 7000, 'remaining': 23000, 'effective': 23000, 'count': 2},
        'INCOME': {'planned': 0, 'abated': 0, 'remaining': 0, 'effective': 0, 'count': 0},
      },
      'counterparts': {
        'INCOME': {'pending': 10000, 'settled': 5000, 'count': 2},
        'EXPENSE': {'pending': 0, 'settled': 0, 'count': 0},
      },
    },
    'GET /reports/cashflow': (_) => {
      'mode': 'cumulative',
      'basis': 'projected',
      'granularity': 'month',
      'from': '2026-10-01',
      'to': '2026-12-31',
      'openingBalance': 100000,
      'closingBalance': 250000,
      'totals': {'income': 900000, 'expense': 750000, 'transfersIn': 0, 'transfersOut': 0, 'net': 150000},
      'buckets': [
        {
          'start': '2026-10-01',
          'end': '2026-10-31',
          'income': 300000,
          'expense': 250000,
          'transfersIn': 0,
          'transfersOut': 0,
          'net': 50000,
          'opening': 100000,
          'closing': 150000,
        },
        {
          'start': '2026-11-01',
          'end': '2026-11-30',
          'income': 300000,
          'expense': 350000,
          'transfersIn': 0,
          'transfersOut': 0,
          'net': -50000,
          'opening': 150000,
          'closing': 100000,
        },
        {
          'start': '2026-12-01',
          'end': '2026-12-31',
          'income': 300000,
          'expense': 150000,
          'transfersIn': 0,
          'transfersOut': 0,
          'net': 150000,
          'opening': 100000,
          'closing': 250000,
        },
      ],
    },
  };

  static const _forecast = {
    'kind': 'transaction',
    'id': 'f1',
    'type': 'EXPENSE',
    'status': 'PENDING',
    'description': 'Gasolina',
    'amount': 10000,
    'date': '2026-11-10',
    'overdue': false,
    'affectsBalance': true,
    'account': {'id': 'a1', 'name': 'Nubank'},
    'category': {'id': 'k1', 'name': 'Compras', 'color': '#AD1457', 'icon': 'shopping_bag'},
    'recurrenceId': null,
    'forecast': {'state': 'OPEN', 'planned': 10000, 'abated': 7000, 'remaining': 3000, 'effective': 3000},
  };

  static const _invoice = {
    'id': 'i1',
    'refMonth': '2026-12-01',
    'closingDate': '2026-12-05',
    'dueDate': '2026-12-12',
    'total': 46000,
    'paid': 0,
    'remaining': 46000,
    'status': 'OPEN',
  };
}

/// Monta [home] com tela de celular, sessão logada na API falsa e catálogo carregado.
Future<FakeApi> pumpScreen(WidgetTester tester, Widget home, {FakeApi? api, AppSettings? settings}) async {
  SewFonts.enabled = false; // sem rede nos testes
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final fake = api ?? FakeApi();
  // Lado nativo da leitura de notificações (BankNotificationService): sem acesso liberado, fila vazia.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('sewwallet/notifications'),
    (call) async => switch (call.method) {
      'isGranted' => false,
      'queueSize' || 'flush' => 0,
      'seenApps' => '{"com.whatsapp":"WhatsApp"}',
      'log' => '[]',
      _ => null,
    },
  );
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
  body: Builder(
    builder: (ctx) => Center(
      child: TextButton(onPressed: () => open(ctx), child: const Text('abrir')),
    ),
  ),
);

Future<void> tapText(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    // Listas só constroem o que está na tela: rola até o texto aparecer.
    await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
  }
  final f = find.text(text).last;
  // Como no aparelho ao tocar fora do campo: tira o foco, senão o campo puxa a rolagem de volta.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}
