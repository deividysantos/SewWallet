import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sewwallet/models/ledger.dart';
import 'package:sewwallet/screens/accounts_screen.dart';
import 'package:sewwallet/screens/cards_screen.dart';
import 'package:sewwallet/screens/home_shell.dart';
import 'package:sewwallet/screens/reports_screen.dart';
import 'package:sewwallet/screens/transaction_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api.dart';

Finder field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    SharedPreferences.setMockInitialValues({});
  });

  group('Novo lançamento', () {
    testWidgets('compra parcelada no cartão', (tester) async {
      final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx)));
      await tapText(tester, 'abrir');

      await tester.enterText(field('Valor'), '120000');
      await tester.enterText(field('Descrição'), 'Celular');
      await tapText(tester, 'Cartão');
      expect(find.textContaining('Entra na fatura que vence em'), findsOneWidget);

      await tapText(tester, 'Parcelado');
      await tester.enterText(field('Parcelas'), '3');
      await tester.pumpAndSettle();
      expect(find.textContaining('3× de'), findsOneWidget);

      await tapText(tester, 'Salvar');
      final body = api.lastBody('POST', '/transactions');
      expect(body['type'], 'EXPENSE');
      expect(body['amount'], 120000);
      expect(body['cardId'], 'c1');
      expect(body.containsKey('accountId'), isFalse);
      expect(body.containsKey('status'), isFalse);
      expect(body['installments'], {'total': 3, 'amountIs': 'total'});
      expect(find.text('Novo lançamento'), findsNothing, reason: 'o formulário fecha depois de salvar');
    });

    testWidgets('despesa pendente na conta', (tester) async {
      final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx)));
      await tapText(tester, 'abrir');

      await tester.enterText(field('Valor'), '5000');
      await tester.enterText(field('Descrição'), 'Luz');
      await tapText(tester, 'Pago');
      await tapText(tester, 'Salvar');

      final body = api.lastBody('POST', '/transactions');
      expect(body['accountId'], 'a1');
      expect(body['status'], 'PENDING');
      expect(body['amount'], 5000);
      expect(body.containsKey('installments'), isFalse);
    });

    testWidgets('transferência entre contas', (tester) async {
      final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx)));
      await tapText(tester, 'abrir');

      await tapText(tester, 'Transf.');
      await tester.enterText(field('Valor'), '100000');
      await tester.enterText(field('Descrição'), 'Reserva');
      await tapText(tester, 'Salvar');

      final body = api.lastBody('POST', '/transactions');
      expect(body['type'], 'TRANSFER');
      expect(body['accountId'], 'a1');
      expect(body['toAccountId'], 'a2');
      expect(body.containsKey('categoryId'), isFalse);
    });

    testWidgets('fixo mensal', (tester) async {
      final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx)));
      await tapText(tester, 'abrir');

      await tester.enterText(field('Valor'), '180000');
      await tester.enterText(field('Descrição'), 'Aluguel');
      await tapText(tester, 'Fixo');
      await tapText(tester, 'Salvar');

      expect(api.lastBody('POST', '/transactions')['recurrence'], {'frequency': 'MONTHLY'});
    });

    testWidgets('valor obrigatório', (tester) async {
      final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx)));
      await tapText(tester, 'abrir');
      await tester.enterText(field('Descrição'), 'Sem valor');
      await tapText(tester, 'Salvar');
      expect(find.text('Informe o valor'), findsOneWidget);
      expect(api.calls('POST', '/transactions'), isEmpty);
    });
  });

  testWidgets('editar parcela pergunta o escopo', (tester) async {
    final tx = TxItem(
      id: 't2',
      type: TxType.expense,
      paid: true,
      description: 'Notebook',
      amount: 48000,
      date: DateTime(2026, 11, 14),
      overdue: false,
      affectsBalance: false,
      card: const Ref('c1', 'Roxinho'),
      installmentNumber: 3,
      installmentTotal: 10,
    );
    final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx, existing: tx)));
    await tapText(tester, 'abrir');
    expect(find.text('Parcela 3/10'), findsOneWidget);

    await tester.enterText(field('Descrição'), 'Notebook Dell');
    await tapText(tester, 'Salvar');
    await tapText(tester, 'Este e os próximos');

    final req = api.calls('PUT', '/transactions/t2').single;
    expect(req.url.queryParameters['scope'], 'future');
    final body = api.lastBody('PUT', '/transactions/t2');
    expect(body['description'], 'Notebook Dell');
    expect(body.containsKey('date'), isFalse, reason: 'data só muda em "Só este"');
  });

  testWidgets('contas: lista, totais e nova conta com saldo negativo', (tester) async {
    final api = await pumpScreen(tester, const AccountsScreen());
    expect(find.text('Nubank'), findsOneWidget);
    expect(find.text('Itaú'), findsOneWidget);
    expect(find.textContaining('7.000,00'), findsOneWidget); // 5.000 + 2.000

    await tester.tap(find.byTooltip('Nova conta'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Nome'), 'Inter');
    await tester.enterText(field('Saldo inicial'), '25000');
    await tester.tap(find.byTooltip('Tornar negativo'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Salvar');

    final body = api.lastBody('POST', '/accounts');
    expect(body['name'], 'Inter');
    expect(body['initialBalance'], -25000);
    expect(body['type'], 'CHECKING');
  });

  testWidgets('cartões: fatura com compras e pagamento parcial', (tester) async {
    final api = await pumpScreen(tester, const CardsScreen());
    expect(find.text('Roxinho'), findsOneWidget);
    expect(find.textContaining('disponível'), findsOneWidget);

    await tapText(tester, 'Roxinho');
    expect(find.text('Fatura de Dezembro 2026'), findsOneWidget);
    expect(find.textContaining('Notebook'), findsOneWidget);
    expect(find.textContaining('− R\$'), findsOneWidget, reason: 'estorno aparece abatendo');

    await tapText(tester, 'Antecipar pagamento');
    await tester.enterText(field('Valor'), '20000');
    await tapText(tester, 'Lançar pagamento');

    final body = api.lastBody('POST', '/invoices/i1/payments');
    expect(body['amount'], 20000);
    expect(body['accountId'], 'a1');
    expect(body['status'], 'PAID');
  });

  testWidgets('cartões: novo cartão', (tester) async {
    final api = await pumpScreen(tester, const CardsScreen());
    await tester.tap(find.byTooltip('Novo cartão'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Nome'), 'Inter Black');
    await tester.enterText(field('Limite (opcional)'), '1000000');
    await tapText(tester, 'Salvar');

    final body = api.lastBody('POST', '/cards');
    expect(body['name'], 'Inter Black');
    expect(body['limit'], 1000000);
    expect(body['paymentAccountId'], 'a1');
    expect(body['closingDayInNext'], isTrue);
  });

  testWidgets('relatórios: totais, tabela e troca para "Só o período"', (tester) async {
    final api = await pumpScreen(tester, const ReportsScreen());
    expect(find.text('Saldo final'), findsWidgets);
    expect(find.text('Out/26'), findsWidgets);

    await tapText(tester, 'Só o período');
    expect(api.calls('GET', '/reports/cashflow').last.url.queryParameters['mode'], 'period');

    await tapText(tester, 'Semana');
    final q = api.calls('GET', '/reports/cashflow').last.url.queryParameters;
    expect(q['granularity'], 'week');
    expect(q['basis'], 'projected');
  });

  testWidgets('navega por todas as abas', (tester) async {
    final api = await pumpScreen(tester, const HomeShell());
    expect(find.text('Conta de luz'), findsOneWidget);
    expect(find.text('Fatura Roxinho'), findsOneWidget);

    for (final tab in ['Contas', 'Cartões', 'Relatórios', 'Lançamentos']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
    }

    // Marcar como pago chama a API e recarrega.
    await tester.tap(find.byTooltip('Pendente — marcar como pago'));
    await tester.pumpAndSettle();
    expect(api.lastBody('PATCH', '/transactions/t1/status'), {'status': 'PAID'});
  });
}
