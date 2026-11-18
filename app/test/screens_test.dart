import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sewwallet/models/ledger.dart';
import 'package:sewwallet/screens/accounts_screen.dart';
import 'package:sewwallet/screens/cards_screen.dart';
import 'package:sewwallet/screens/cashflow_report_screen.dart';
import 'package:sewwallet/screens/settings_screen.dart';
import 'package:sewwallet/screens/transactions_screen.dart';
import 'package:sewwallet/state/settings.dart';
import 'package:sewwallet/theme.dart';
import 'package:sewwallet/util/format.dart';
import 'package:sewwallet/screens/categories_screen.dart';
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
    SewFonts.enabled = false; // sem rede nos testes
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

  testWidgets('relatórios: a aba lista os relatórios e abre o fluxo de caixa', (tester) async {
    final api = await pumpScreen(tester, const ReportsScreen());
    expect(api.calls('GET', '/reports/cashflow'), isEmpty);
    await tapText(tester, 'Fluxo de caixa');
    expect(api.calls('GET', '/reports/cashflow'), hasLength(1));
    expect(find.text('Saldo final'), findsWidgets);
  });

  testWidgets('fluxo de caixa: setas andam pelo período', (tester) async {
    final api = await pumpScreen(tester, const CashflowReportScreen());
    final year = DateTime.now().year;
    final first = api.calls('GET', '/reports/cashflow').last.url.queryParameters;
    expect(first['granularity'], 'month');
    expect(first['from'], '$year-01-01', reason: 'visão por mês = ano de calendário');
    expect(first['to'], '$year-12-31');
    expect(find.text('$year'), findsOneWidget);

    await tester.tap(find.byTooltip('Próximo (ano)'));
    await tester.pumpAndSettle();
    final next = api.calls('GET', '/reports/cashflow').last.url.queryParameters;
    expect(next['from'], '${year + 1}-01-01');
    expect(find.text('${year + 1}'), findsOneWidget);

    await tester.tap(find.byTooltip('Anterior (ano)'));
    await tester.pumpAndSettle();
    expect(api.calls('GET', '/reports/cashflow').last.url.queryParameters['from'], first['from']);
  });

  testWidgets('fluxo de caixa: por semana mostra o mês, não as datas', (tester) async {
    final api = await pumpScreen(tester, const CashflowReportScreen());
    await tester.tap(find.byTooltip('Mostrar filtros'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Semana');

    // Volta ao topo (a lista rolou até o botão "Semana") e recolhe os filtros.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Recolher filtros'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(find.text(monthTitle(DateTime(now.year, now.month))), findsOneWidget);
    var q = api.calls('GET', '/reports/cashflow').last.url.queryParameters;
    var from = DateTime.parse(q['from']!);
    var to = DateTime.parse(q['to']!);
    expect(from.weekday, DateTime.monday);
    expect(to.weekday, DateTime.sunday);
    expect(from.isAfter(DateTime(now.year, now.month, 1)), isFalse);
    expect(to.isBefore(DateTime(now.year, now.month + 1, 0)), isFalse);

    // Atravessa fevereiro (28/29 dias) sem desalinhar: sempre começa no mês certo.
    for (var i = 1; i <= 4; i++) {
      await tester.tap(find.byTooltip('Próximo (mês)'));
      await tester.pumpAndSettle();
      final m = DateTime(now.year, now.month + i);
      expect(find.text(monthTitle(m)), findsOneWidget);
      q = api.calls('GET', '/reports/cashflow').last.url.queryParameters;
      from = DateTime.parse(q['from']!);
      to = DateTime.parse(q['to']!);
      expect(from.isAfter(m), isFalse);
      expect(m.difference(from).inDays, lessThan(7));
      expect(to.isBefore(DateTime(m.year, m.month + 1, 0)), isFalse);
    }
  });

  testWidgets('relatórios: totais, tabela e troca para "Só o período"', (tester) async {
    final api = await pumpScreen(tester, const CashflowReportScreen());
    expect(find.text('Saldo final'), findsWidgets);
    expect(find.text('Outubro'), findsWidgets, reason: 'linhas com o nome do mês');
    expect(find.text('Só o período'), findsNothing, reason: 'filtros começam recolhidos');

    await tester.tap(find.byTooltip('Mostrar filtros'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Só o período');
    expect(api.calls('GET', '/reports/cashflow').last.url.queryParameters['mode'], 'period');

    await tapText(tester, 'Semana');
    final q = api.calls('GET', '/reports/cashflow').last.url.queryParameters;
    expect(q['granularity'], 'week');
    expect(q['basis'], 'projected');
  });

  group('Categorias', () {
    testWidgets('lista por tipo e cria categoria com ícone', (tester) async {
      final api = await pumpScreen(tester, const CategoriesScreen());
      expect(find.text('Compras'), findsOneWidget);
      expect(find.text('Salário'), findsNothing);
      await tapText(tester, 'Receitas');
      expect(find.text('Salário'), findsOneWidget);
      await tapText(tester, 'Despesas');

      await tester.tap(find.byTooltip('Nova categoria'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Nome'), 'Pets');
      final pets = find.byTooltip('pets');
      await tester.ensureVisible(pets);
      await tester.tap(pets);
      await tester.pumpAndSettle();
      await tapText(tester, 'Salvar');

      expect(api.lastBody('POST', '/categories'), {'name': 'Pets', 'color': '#820AD1', 'icon': 'pets', 'kind': 'EXPENSE'});
    });

    testWidgets('editar não muda o tipo; excluir pede confirmação', (tester) async {
      final api = await pumpScreen(tester, const CategoriesScreen());
      await tapText(tester, 'Compras');
      await tester.enterText(field('Nome'), 'Compras online');
      await tapText(tester, 'Salvar');
      final body = api.lastBody('PUT', '/categories/k1');
      expect(body['name'], 'Compras online');
      expect(body.containsKey('kind'), isFalse);

      await tapText(tester, 'Compras');
      await tester.tap(find.byTooltip('Excluir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ficam sem categoria'), findsOneWidget);
      await tapText(tester, 'Excluir');
      expect(api.calls('DELETE', '/categories/k1'), hasLength(1));
    });
  });

  testWidgets('relatórios: filtro por conta', (tester) async {
    final api = await pumpScreen(tester, const CashflowReportScreen());
    await tester.tap(find.byTooltip('Mostrar filtros'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Todas as contas');
    await tapText(tester, 'Itaú');
    await tapText(tester, 'Aplicar');
    expect(api.calls('GET', '/reports/cashflow').last.url.queryParameters['accountIds'], 'a2');
    expect(find.text('Itaú'), findsWidgets, reason: 'o resumo e o botão mostram a conta escolhida');

    await tapText(tester, 'Itaú');
    await tapText(tester, 'Todas');
    await tapText(tester, 'Aplicar');
    expect(api.calls('GET', '/reports/cashflow').last.url.queryParameters.containsKey('accountIds'), isFalse);
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

  testWidgets('configurações: compras no cartão pela data do pagamento', (tester) async {
    final settings = AppSettings();
    final api = await pumpScreen(tester, const TransactionsScreen(), settings: settings);
    expect(api.calls('GET', '/transactions').last.url.queryParameters['cardDate'], 'purchase');

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Configurações');
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tapText(tester, 'Data do pagamento');

    expect(settings.cardDateView, CardDateView.payment);
    expect(api.calls('GET', '/transactions').last.url.queryParameters['cardDate'], 'payment');
  });

  testWidgets('novo lançamento: cria categoria sem sair do formulário', (tester) async {
    final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx)));
    await tapText(tester, 'abrir');
    await tester.enterText(field('Valor'), '5000');
    await tester.enterText(field('Descrição'), 'Ração');

    await tapText(tester, 'Sem categoria');
    await tapText(tester, 'Nova categoria…');
    expect(find.text('Nova categoria'), findsOneWidget);
    await tester.enterText(field('Nome'), 'Pets');
    await tapText(tester, 'Salvar');

    expect(api.lastBody('POST', '/categories')['kind'], 'EXPENSE');
    expect(find.text('Novo lançamento'), findsOneWidget, reason: 'volta para o formulário');
    expect(find.widgetWithText(TextFormField, 'Descrição'), findsOneWidget);
    await tapText(tester, 'Salvar');
    expect(api.lastBody('POST', '/transactions')['categoryId'], 'k3');
  });
}
