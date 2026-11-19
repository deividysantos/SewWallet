import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sewwallet/models/ledger.dart';
import 'package:sewwallet/screens/accounts_screen.dart';
import 'package:sewwallet/screens/cards_screen.dart';
import 'package:sewwallet/screens/cashflow_report_screen.dart';
import 'package:sewwallet/screens/category_report_screen.dart';
import 'package:sewwallet/screens/counterpart_report_screen.dart';
import 'package:sewwallet/screens/saved_filters_screen.dart';
import 'package:sewwallet/screens/card_form.dart';
import 'package:sewwallet/screens/card_detail_screen.dart';
import 'package:sewwallet/screens/notification_settings_screen.dart';
import 'package:sewwallet/screens/suggestions_screen.dart';
import 'package:sewwallet/state/catalog.dart';
import 'package:provider/provider.dart';
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
      final api = await pumpScreen(
        tester,
        launcher((ctx) => TransactionForm.open(ctx, type: TxType.expense, card: true)),
      );
      await tapText(tester, 'abrir');
      expect(find.text('Compra no cartão'), findsOneWidget);
      expect(find.text('Receita'), findsNothing, reason: 'o tipo vem do botão +');

      await tester.enterText(field('Valor'), '120000');
      await tester.enterText(field('Descrição'), 'Celular');
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
      expect(find.text('Compra no cartão'), findsNothing, reason: 'o formulário fecha depois de salvar');
    });

    testWidgets('compra no cartão com contrapartida', (tester) async {
      final api = await pumpScreen(
        tester,
        launcher((ctx) => TransactionForm.open(ctx, type: TxType.expense, card: true)),
      );
      await tapText(tester, 'abrir');

      await tester.enterText(field('Valor'), '10000');
      await tester.enterText(field('Descrição'), 'Fone para Ana');
      await tapText(tester, 'Gerar contrapartida');
      expect(find.textContaining('no vencimento da fatura'), findsOneWidget);
      await tapText(tester, 'Salvar');

      final body = api.lastBody('POST', '/transactions');
      expect(body['cardId'], 'c1');
      expect(body['counterpart'], isTrue);
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
      final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx, type: TxType.transfer)));
      await tapText(tester, 'abrir');
      expect(find.text('Nova transferência'), findsOneWidget);

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

  group('Previsões', () {
    testWidgets('nova previsão não tem "Pago" nem parcelado', (tester) async {
      final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx)));
      await tapText(tester, 'abrir');

      await tapText(tester, 'É uma previsão');
      expect(find.text('Previsão a pagar'), findsOneWidget);
      expect(find.text('Pago'), findsNothing);
      expect(find.textContaining('Abater de uma previsão'), findsNothing);

      await tester.enterText(field('Valor previsto'), '20000');
      await tester.enterText(field('Descrição'), 'Gasolina');
      await tapText(tester, 'Salvar');

      final body = api.lastBody('POST', '/transactions');
      expect(body['isForecast'], isTrue);
      expect(body['amount'], 20000);
      expect(body.containsKey('status'), isFalse);
      expect(body.containsKey('forecastId'), isFalse);
    });

    testWidgets('lançamento real abate uma previsão e pode encerrá-la', (tester) async {
      final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx)));
      await tapText(tester, 'abrir');

      await tester.enterText(field('Valor'), '9500');
      await tapText(tester, 'Abater de uma previsão (opcional)');
      expect(api.calls('GET', '/transactions/forecasts/open').single.url.queryParameters['type'], 'EXPENSE');
      await tapText(tester, 'Gasolina');
      expect(find.text('Abate de: Gasolina'), findsOneWidget);
      await tapText(tester, 'Encerrar a previsão após salvar');
      await tapText(tester, 'Salvar');

      final body = api.lastBody('POST', '/transactions');
      expect(body['forecastId'], 'f1');
      expect(body['description'], 'Gasolina', reason: 'descrição vazia herda a da previsão');
      expect(body['categoryId'], 'k1');
      expect(api.lastBody('PATCH', '/transactions/f1/forecast-state'), {'state': 'CLOSED'});
    });

    testWidgets('lista: "Considerar previsões" vai na consulta', (tester) async {
      final api = await pumpScreen(tester, const TransactionsScreen());
      expect(api.calls('GET', '/transactions').last.url.queryParameters['forecasts'], 'true');

      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Considerar previsões');
      await tapText(tester, 'Aplicar');
      expect(api.calls('GET', '/transactions').last.url.queryParameters['forecasts'], 'false');
    });

    testWidgets('configuração muda o padrão dos relatórios', (tester) async {
      final settings = AppSettings()..includeForecasts = false;
      final api = await pumpScreen(tester, const CashflowReportScreen(), settings: settings);
      expect(api.calls('GET', '/reports/cashflow').last.url.queryParameters['forecasts'], 'false');
    });

    testWidgets('relatório de previsões: fixas, avulsas e abatimentos', (tester) async {
      final api = await pumpScreen(tester, const ReportsScreen());
      await tapText(tester, 'Previsões');
      final q = api.calls('GET', '/reports/forecasts').last.url.queryParameters;
      final now = DateTime.now();
      expect(q['month'], apiDate(DateTime(now.year, now.month)));
      expect(find.text('Fixas'), findsOneWidget);
      expect(find.text('Avulsas deste mês'), findsOneWidget);
      expect(find.text('Mercado'), findsOneWidget);

      await tapText(tester, 'Gasolina');
      expect(find.text('Posto Shell'), findsOneWidget);
      await tapText(tester, 'Encerrar previsão');
      expect(api.lastBody('PATCH', '/transactions/f1/forecast-state'), {'state': 'CLOSED'});
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

  testWidgets('por categoria: total, comparação, aviso de sem categoria e detalhe', (tester) async {
    final api = await pumpScreen(tester, const CategoryReportScreen());
    final now = DateTime.now();
    final q = api.calls('GET', '/reports/categories').last.url.queryParameters;
    expect(q['kind'], 'EXPENSE');
    expect(q['from'], apiDate(DateTime(now.year, now.month, 1)));
    expect(q['to'], apiDate(DateTime(now.year, now.month + 1, 0)));
    expect(q['cardDate'], 'payment', reason: 'agrupado na fatura = gasto no mês do vencimento');

    expect(find.textContaining('▲ 25%'), findsOneWidget, reason: 'R\$ 1.000 vs R\$ 800');
    expect(find.textContaining('40% está sem categoria'), findsOneWidget);
    expect(find.text('Compras'), findsOneWidget);

    await tapText(tester, 'Receitas');
    expect(api.calls('GET', '/reports/categories').last.url.queryParameters['kind'], 'INCOME');
    await tapText(tester, 'Despesas');

    await tapText(tester, 'Compras');
    final d = api.calls('GET', '/reports/categories/detail').last.url.queryParameters;
    expect(d['categoryId'], 'k1');
    expect(find.text('Notebook'), findsOneWidget);
    expect(find.textContaining('− R\$'), findsOneWidget, reason: 'estorno abate');
  });

  testWidgets('por categoria: "sem categoria" abre o detalhe com categoryId=none', (tester) async {
    final api = await pumpScreen(tester, const CategoryReportScreen());
    await tapText(tester, 'Sem categoria');
    expect(api.calls('GET', '/reports/categories/detail').last.url.queryParameters['categoryId'], 'none');
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

      expect(api.lastBody('POST', '/categories'), {
        'name': 'Pets',
        'color': '#820AD1',
        'icon': 'pets',
        'kind': 'EXPENSE',
      });
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
    // Abre no Início (painel do mês).
    expect(find.text('Resultado do mês'), findsOneWidget);
    for (final tab in ['Contas', 'Cartões', 'Relatórios', 'Início', 'Lançamentos']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
    }
    expect(find.text('Conta de luz'), findsOneWidget);
    expect(find.text('Fatura Roxinho'), findsOneWidget);

    // Marcar como pago chama a API e recarrega.
    await tester.tap(find.byTooltip('Pendente — marcar como pago'));
    await tester.pumpAndSettle();
    expect(api.lastBody('PATCH', '/transactions/t1/status'), {'status': 'PAID'});
  });

  testWidgets('configurações: compras no cartão pela data do pagamento', (tester) async {
    final settings = AppSettings();
    final api = await pumpScreen(tester, const TransactionsScreen(), settings: settings);
    expect(
      api.calls('GET', '/transactions').last.url.queryParameters['cardDate'],
      'invoice',
      reason: 'padrão: compras agrupadas na fatura',
    );

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Configurações');
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Data do pagamento, agrupadas na fatura'), findsOneWidget);
    expect(find.text('Data do pagamento'), findsNothing, reason: 'não há mais opção separada');
    await tapText(tester, 'Data da compra');

    expect(settings.cardDateView, CardDateView.purchase);
    expect(api.calls('GET', '/transactions').last.url.queryParameters['cardDate'], 'purchase');
  });

  testWidgets('tela inicial: tocar na fatura abre o detalhe com as compras', (tester) async {
    await pumpScreen(tester, const TransactionsScreen());
    await tapText(tester, 'Fatura Roxinho');
    expect(find.text('Fatura de Dezembro 2026'), findsOneWidget);
    expect(find.textContaining('Notebook'), findsOneWidget);
  });

  testWidgets('novo lançamento: cria categoria sem sair do formulário', (tester) async {
    final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx)));
    await tapText(tester, 'abrir');
    await tester.enterText(field('Valor'), '5000');
    await tester.enterText(field('Descrição'), 'Ração');

    await tapText(tester, 'Sem categoria');
    expect(find.text('Categoria da despesa'), findsOneWidget, reason: 'abre a folha de categorias');
    await tapText(tester, 'Nova categoria…');
    expect(find.text('Nova categoria'), findsOneWidget);
    await tester.enterText(field('Nome'), 'Pets');
    await tapText(tester, 'Salvar');

    expect(api.lastBody('POST', '/categories')['kind'], 'EXPENSE');
    expect(find.text('Nova despesa'), findsOneWidget, reason: 'volta para o formulário');
    expect(find.widgetWithText(TextFormField, 'Descrição'), findsOneWidget);
    await tapText(tester, 'Salvar');
    expect(api.lastBody('POST', '/transactions')['categoryId'], 'k3');
  });

  group('Novidades 0.7', () {
    testWidgets('botão +: some e mostra os atalhos; Cartão abre compra no cartão', (tester) async {
      final api = await pumpScreen(tester, const TransactionsScreen());
      await tester.tap(find.byTooltip('Novo lançamento'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Novo lançamento'), findsNothing, reason: 'o + some');
      for (final t in ['Despesa', 'Receita', 'Transferência', 'Cartão']) {
        expect(find.byTooltip(t), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Cartão'));
      await tester.pumpAndSettle();
      expect(find.text('Compra no cartão'), findsOneWidget);
      await tester.enterText(field('Valor'), '2500');
      await tester.enterText(field('Descrição'), 'Livro');
      await tapText(tester, 'Salvar');
      final body = api.lastBody('POST', '/transactions');
      expect(body['type'], 'EXPENSE');
      expect(body['cardId'], 'c1');
    });

    testWidgets('botão +: Receita abre o formulário de receita', (tester) async {
      await pumpScreen(tester, const TransactionsScreen());
      await tester.tap(find.byTooltip('Novo lançamento'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Receita'));
      await tester.pumpAndSettle();
      expect(find.text('Nova receita'), findsOneWidget);
    });

    testWidgets('categoria: escolhe na folha em grade', (tester) async {
      final api = await pumpScreen(tester, launcher((ctx) => TransactionForm.open(ctx, type: TxType.expense)));
      await tapText(tester, 'abrir');
      await tester.enterText(field('Valor'), '3000');
      await tester.enterText(field('Descrição'), 'Mercado');
      await tapText(tester, 'Sem categoria');
      await tapText(tester, 'Compras');
      expect(find.text('Categoria da despesa'), findsNothing, reason: 'a folha fecha');
      await tapText(tester, 'Salvar');
      expect(api.lastBody('POST', '/transactions')['categoryId'], 'k1');
    });

    testWidgets('início: painel do mês, filtros e filtro preferido', (tester) async {
      final api = await pumpScreen(tester, const HomeShell());
      expect(find.text('Saldo das contas'), findsOneWidget);
      expect(find.text('Resultado do mês'), findsOneWidget);
      expect(find.text('Fatura Roxinho'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('dashCounterparts')));
      await tester.pumpAndSettle();
      expect(api.calls('GET', '/reports/dashboard').last.url.queryParameters['counterparts'], 'false');

      await tester.tap(find.byKey(const ValueKey('preferredFilter')).first);
      await tester.pumpAndSettle();
      await tapText(tester, 'Salvar como filtro preferido');
      final saved = api.lastBody('PUT', '/report-filters/dashboard')['params'] as Map;
      expect(saved['counterparts'], isFalse);
      expect(saved.containsKey('month'), isFalse, reason: 'o mês não é salvo');

      await tester.scrollUntilVisible(find.text('Maiores gastos'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Compras'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('A RECEBER DE VOLTA'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('FALTA PAGAR'), findsOneWidget, reason: 'previsões do mês');
    });

    testWidgets('filtro preferido abre sozinho no relatório', (tester) async {
      final fake = FakeApi()
        ..preferred = [
          {
            'report': 'cashflow',
            'params': {
              'gran': 'day',
              'cumulative': false,
              'projected': true,
              'forecasts': false,
              'accountIds': ['a2'],
            },
          },
        ];
      final api = await pumpScreen(tester, const CashflowReportScreen(), api: fake);
      final q = api.calls('GET', '/reports/cashflow').first.url.queryParameters;
      expect(q['granularity'], 'day');
      expect(q['mode'], 'period');
      expect(q['forecasts'], 'false');
      expect(q['accountIds'], 'a2');
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('filtros salvos: lista e remove', (tester) async {
      final fake = FakeApi()
        ..preferred = [
          {
            'report': 'cashflow',
            'params': {
              'gran': 'week',
              'accountIds': ['a1'],
            },
          },
        ];
      final api = await pumpScreen(tester, const SavedFiltersScreen(), api: fake);
      expect(find.textContaining('Por semana'), findsOneWidget);
      expect(find.textContaining('Nubank'), findsOneWidget);
      await tester.tap(find.byTooltip('Remover'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Remover');
      expect(api.calls('DELETE', '/report-filters/cashflow'), hasLength(1));
      expect(find.byTooltip('Remover'), findsNothing);
    });

    testWidgets('contrapartidas: totais, pendentes e marcar como recebida', (tester) async {
      final api = await pumpScreen(tester, const CounterpartReportScreen());
      expect(find.text('A receber de volta'), findsOneWidget);
      expect(find.text('Pendentes'), findsOneWidget);
      expect(find.text('Quitadas'), findsOneWidget);
      expect(find.text('Fone para Ana'), findsOneWidget);
      await tapText(tester, 'Fone para Ana');
      await tapText(tester, 'Marcar como recebida');
      expect(api.lastBody('PATCH', '/transactions/cp1/status'), {'status': 'PAID'});
    });

    testWidgets('relatórios: lista o de contrapartidas', (tester) async {
      await pumpScreen(tester, const ReportsScreen());
      expect(find.text('Contrapartidas'), findsOneWidget);
    });
  });

  group('Notificações dos bancos', () {
    testWidgets('início: aviso de sugestões abre a lista', (tester) async {
      final fake = FakeApi()..suggestionCount = 2;
      await pumpScreen(tester, const HomeShell(), api: fake);
      expect(find.text('2 sugestões de lançamento'), findsOneWidget);
      await tapText(tester, '2 sugestões de lançamento');
      expect(find.text('Sugestões'), findsOneWidget);
      expect(find.text('Posto Shell'), findsOneWidget);
    });

    testWidgets('sugestão: criar lançamento vem preenchido e marca como aceita', (tester) async {
      final api = await pumpScreen(tester, const SuggestionsScreen());
      expect(find.textContaining('POSTO SHELL'), findsOneWidget, reason: 'mostra o texto da notificação');
      await tapText(tester, 'Criar lançamento');
      expect(find.text('Compra no cartão'), findsOneWidget);
      await tapText(tester, 'Salvar');
      final body = api.lastBody('POST', '/transactions');
      expect(body['amount'], 8740);
      expect(body['description'], 'Posto Shell');
      expect(body['cardId'], 'c1');
      expect(body['categoryId'], 'k1');
      expect(body['date'], '2026-11-19');
      expect(api.lastBody('POST', '/suggestions/s1/accept'), {'transactionId': 'tNew'});
    });

    testWidgets('sugestão: descartar', (tester) async {
      final api = await pumpScreen(tester, const SuggestionsScreen());
      await tapText(tester, 'Descartar');
      expect(api.calls('POST', '/suggestions/s1/dismiss'), hasLength(1));
    });

    testWidgets('processadas: desfazer baixa automática', (tester) async {
      final api = await pumpScreen(tester, const SuggestionsScreen());
      await tapText(tester, 'Processadas');
      expect(find.textContaining('Baixa automática'), findsOneWidget);
      await tapText(tester, 'Desfazer baixa');
      expect(api.calls('POST', '/suggestions/s2/undo'), hasLength(1));
    });

    testWidgets('configuração: sem acesso liberado avisa e ligar grava os bancos lidos', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpScreen(tester, const NotificationSettingsScreen());
      expect(find.text('Acesso às notificações bloqueado'), findsOneWidget);
      expect(find.text('Banco do Brasil'), findsOneWidget, reason: 'bancos conhecidos vêm marcados');
      await tester.tap(find.byKey(const ValueKey('notifEnabled')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notifications.enabled'), isTrue);
      expect(prefs.getString('notifications.apps'), contains('com.nu.production'));
    });

    testWidgets('cartão: final de 4 dígitos vai para a API', (tester) async {
      final api = await pumpScreen(
        tester,
        launcher((ctx) => CardForm.open(ctx, existing: ctx.read<Catalog>().cards.first)),
      );
      await tapText(tester, 'abrir');
      await tester.enterText(find.byKey(const ValueKey('lastDigits')), '4821');
      await tapText(tester, 'Salvar');
      expect(api.lastBody('PUT', '/cards/c1')['lastDigits'], '4821');
    });
  });

  group('Fatura', () {
    testWidgets('compras abrem para editar e previsões do cartão aparecem', (tester) async {
      await pumpScreen(tester, launcher((ctx) => CardDetailScreen.open(ctx, cardId: 'c1', invoiceId: 'i1')));
      await tapText(tester, 'abrir');
      expect(find.text('Previsões (1)'), findsOneWidget);
      expect(find.text('Gasolina no cartão'), findsOneWidget);
      await tapText(tester, 'Notebook  3/10');
      expect(find.text('Editar lançamento'), findsOneWidget, reason: 'abre o formulário da compra');
    });

    testWidgets('previsão da fatura abre a edição da previsão', (tester) async {
      await pumpScreen(tester, launcher((ctx) => CardDetailScreen.open(ctx, cardId: 'c1', invoiceId: 'i1')));
      await tapText(tester, 'abrir');
      await tapText(tester, 'Gasolina no cartão');
      expect(find.text('Editar previsão a pagar'), findsOneWidget);
    });
  });
}
