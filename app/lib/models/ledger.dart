// Modelos das respostas da API. Valores em centavos.

DateTime parseDate(String s) => DateTime.parse(s);

class Ref {
  const Ref(this.id, this.name);
  final String id;
  final String name;

  static Ref? fromJson(dynamic j) => j == null ? null : Ref(j['id'] as String, j['name'] as String);
}

class CategoryRef {
  const CategoryRef({required this.id, required this.name, this.color, this.icon});
  final String id;
  final String name;
  final String? color;
  final String? icon;

  static CategoryRef? fromJson(dynamic j) => j == null
      ? null
      : CategoryRef(
          id: j['id'] as String,
          name: j['name'] as String,
          color: j['color'] as String?,
          icon: j['icon'] as String?,
        );
}

class Balance {
  const Balance({required this.realized, required this.projected});

  /// Só o que já foi pago.
  final int realized;

  /// Pagos + pendentes.
  final int projected;

  factory Balance.fromJson(dynamic j) => Balance(realized: j['realized'] as int, projected: j['projected'] as int);
}

sealed class LedgerItem {
  String get id;
  String get description;
  DateTime get date;

  static LedgerItem fromJson(Map<String, dynamic> j) =>
      j['kind'] == 'invoice' ? InvoiceItem.fromJson(j) : TxItem.fromJson(j);
}

enum TxType { income, expense, transfer }

enum ForecastState { open, closed, expired }

ForecastState parseForecastState(dynamic s) => switch (s) {
  'CLOSED' => ForecastState.closed,
  'EXPIRED' => ForecastState.expired,
  _ => ForecastState.open,
};

/// Dados de uma previsão (lançamento estimado, abatido pelos lançamentos reais).
class ForecastInfo {
  const ForecastInfo({
    required this.state,
    required this.planned,
    required this.abated,
    required this.remaining,
    required this.effective,
  });

  final ForecastState state;

  /// Valor previsto.
  final int planned;

  /// Já abatido pelos lançamentos reais vinculados.
  final int abated;

  /// Quanto falta abater.
  final int remaining;

  /// Quanto conta hoje nos saldos/relatórios (0 se encerrada ou expirada).
  final int effective;

  bool get isOpen => state == ForecastState.open;

  static ForecastInfo? fromJson(dynamic j) => j == null
      ? null
      : ForecastInfo(
          state: parseForecastState(j['state']),
          planned: j['planned'] as int,
          abated: j['abated'] as int? ?? 0,
          remaining: j['remaining'] as int? ?? 0,
          effective: j['effective'] as int? ?? 0,
        );
}

class TxItem extends LedgerItem {
  TxItem({
    required this.id,
    required this.type,
    required this.paid,
    required this.description,
    required this.amount,
    required this.date,
    required this.overdue,
    required this.affectsBalance,
    this.category,
    this.account,
    this.toAccount,
    this.card,
    this.invoiceDueDate,
    this.installmentNumber,
    this.installmentTotal,
    this.recurrenceId,
    this.paysInvoiceId,
    this.notes,
    this.forecast,
    this.forecastId,
    this.counterpartId,
    this.isCounterpart = false,
  });

  @override
  final String id;
  final TxType type;

  /// Lançamento ligado: a contrapartida (se este é a origem) ou a origem (se este é a contrapartida).
  final String? counterpartId;

  /// true = este lançamento é a contrapartida ("Compensação de: ...") de outro.
  final bool isCounterpart;

  bool get hasCounterpart => counterpartId != null && !isCounterpart;

  /// Preenchido quando o lançamento é uma previsão.
  final ForecastInfo? forecast;

  /// Lançamento real: previsão que ele abate.
  final String? forecastId;

  bool get isForecast => forecast != null;
  final bool paid;
  @override
  final String description;
  final int amount;
  @override
  final DateTime date;
  final bool overdue;

  /// false = compra no cartão (entra no saldo pela fatura).
  final bool affectsBalance;
  final CategoryRef? category;
  final Ref? account;
  final Ref? toAccount;
  final Ref? card;

  /// Vencimento da fatura em que a compra no cartão entrou.
  final DateTime? invoiceDueDate;
  final int? installmentNumber;
  final int? installmentTotal;
  final String? recurrenceId;
  final String? paysInvoiceId;
  final String? notes;

  bool get isFixed => recurrenceId != null;

  factory TxItem.fromJson(Map<String, dynamic> j) {
    final inst = j['installment'];
    return TxItem(
      id: j['id'] as String,
      type: switch (j['type']) {
        'INCOME' => TxType.income,
        'TRANSFER' => TxType.transfer,
        _ => TxType.expense,
      },
      paid: j['status'] == 'PAID',
      description: j['description'] as String,
      amount: j['amount'] as int,
      date: parseDate(j['date'] as String),
      overdue: j['overdue'] as bool? ?? false,
      affectsBalance: j['affectsBalance'] as bool? ?? true,
      category: CategoryRef.fromJson(j['category']),
      account: Ref.fromJson(j['account']),
      toAccount: Ref.fromJson(j['toAccount']),
      card: Ref.fromJson(j['card']),
      invoiceDueDate: j['invoice'] == null ? null : parseDate(j['invoice']['dueDate'] as String),
      installmentNumber: inst == null ? null : inst['number'] as int?,
      installmentTotal: inst == null ? null : inst['total'] as int?,
      recurrenceId: j['recurrenceId'] as String?,
      paysInvoiceId: j['paysInvoiceId'] as String?,
      notes: j['notes'] as String?,
      forecast: ForecastInfo.fromJson(j['forecast']),
      forecastId: j['forecastId'] as String?,
      counterpartId: j['counterpart'] == null ? null : j['counterpart']['id'] as String?,
      isCounterpart: j['counterpart'] != null && j['counterpart']['role'] == 'counterpart',
    );
  }
}

enum InvoiceStatus { open, closed, paid, overdue }

class InvoiceItem extends LedgerItem {
  InvoiceItem({
    required this.id,
    required this.description,
    required this.date,
    required this.card,
    required this.account,
    required this.closingDate,
    required this.total,
    required this.paidAmount,
    required this.remaining,
    required this.status,
    this.lastPaidAt,
    this.forecastTotal = 0,
  });

  @override
  final String id;
  @override
  final String description;

  /// Soma das previsões abertas nesta fatura (fora do total e do valor a pagar).
  final int forecastTotal;

  /// Data do último pagamento (quando já houve).
  final DateTime? lastPaidAt;

  /// Vencimento.
  @override
  final DateTime date;
  final Ref? card;
  final Ref? account;
  final DateTime closingDate;
  final int total;
  final int paidAmount;
  final int remaining;
  final InvoiceStatus status;

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
    id: j['id'] as String,
    description: j['description'] as String,
    date: parseDate(j['dueDate'] as String),
    card: Ref.fromJson(j['card']),
    account: Ref.fromJson(j['account']),
    closingDate: parseDate(j['closingDate'] as String),
    total: j['total'] as int,
    paidAmount: j['paid'] as int,
    remaining: j['remaining'] as int,
    status: parseInvoiceStatus(j['status']),
    lastPaidAt: j['lastPaidAt'] == null ? null : parseDate(j['lastPaidAt'] as String),
    forecastTotal: j['forecastTotal'] as int? ?? 0,
  );
}

class DayGroup {
  DayGroup({required this.date, required this.balance, required this.items});
  final DateTime date;

  /// Saldo das contas no FINAL do dia.
  final Balance balance;
  final List<LedgerItem> items;

  factory DayGroup.fromJson(Map<String, dynamic> j) => DayGroup(
    date: parseDate(j['date'] as String),
    balance: Balance.fromJson(j['balance']),
    items: [for (final i in j['items'] as List) LedgerItem.fromJson(i as Map<String, dynamic>)],
  );
}

class TransactionsPage {
  TransactionsPage({
    required this.today,
    required this.opening,
    required this.closing,
    required this.income,
    required this.expense,
    required this.cardExpense,
    required this.days,
  });

  final DateTime today;
  final Balance opening;
  final Balance closing;
  final int income;
  final int expense;
  final int cardExpense;
  final List<DayGroup> days;

  factory TransactionsPage.fromJson(Map<String, dynamic> j) => TransactionsPage(
    today: parseDate(j['today'] as String),
    opening: Balance.fromJson(j['openingBalance']),
    closing: Balance.fromJson(j['closingBalance']),
    income: j['summary']['income'] as int,
    expense: j['summary']['expense'] as int,
    cardExpense: j['summary']['cardExpense'] as int,
    days: [for (final d in j['days'] as List) DayGroup.fromJson(d as Map<String, dynamic>)],
  );
}

const accountTypes = <String, String>{
  'CHECKING': 'Conta corrente',
  'SAVINGS': 'Poupança',
  'WALLET': 'Carteira',
  'INVESTMENT': 'Investimento',
  'OTHER': 'Outra',
};

class Account {
  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.initialBalance,
    required this.balance,
    required this.projectedMonthEnd,
    required this.archived,
    this.color,
  });

  final String id;
  final String name;
  final String type;
  final int initialBalance;

  /// Saldo atual (só pagos até hoje).
  final int balance;

  /// Previsto para o fim do mês (pagos + pendentes).
  final int projectedMonthEnd;
  final bool archived;
  final String? color;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['id'] as String,
    name: j['name'] as String,
    type: j['type'] as String? ?? 'CHECKING',
    initialBalance: j['initialBalance'] as int? ?? 0,
    balance: j['balance'] as int,
    projectedMonthEnd: j['projectedMonthEnd'] as int,
    archived: j['archived'] as bool? ?? false,
    color: j['color'] as String?,
  );
}

class Category {
  Category({required this.id, required this.name, required this.isIncome, this.color, this.icon});

  final String id;
  final String name;
  final bool isIncome;
  final String? color;
  final String? icon;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String,
    name: j['name'] as String,
    isIncome: j['kind'] == 'INCOME',
    color: j['color'] as String?,
    icon: j['icon'] as String?,
  );
}

InvoiceStatus parseInvoiceStatus(dynamic s) => switch (s) {
  'OPEN' => InvoiceStatus.open,
  'PAID' => InvoiceStatus.paid,
  'OVERDUE' => InvoiceStatus.overdue,
  _ => InvoiceStatus.closed,
};

/// Resumo de uma fatura (lista de faturas do cartão / fatura atual).
class InvoiceSummary {
  InvoiceSummary({
    required this.id,
    required this.refMonth,
    required this.closingDate,
    required this.dueDate,
    required this.total,
    required this.paid,
    required this.remaining,
    required this.status,
  });

  /// null quando a fatura ainda não tem nenhuma compra.
  final String? id;
  final DateTime refMonth;
  final DateTime closingDate;
  final DateTime dueDate;
  final int total;
  final int paid;
  final int remaining;
  final InvoiceStatus status;

  factory InvoiceSummary.fromJson(Map<String, dynamic> j) => InvoiceSummary(
    id: j['id'] as String?,
    refMonth: parseDate(j['refMonth'] as String),
    closingDate: parseDate(j['closingDate'] as String),
    dueDate: parseDate(j['dueDate'] as String),
    total: j['total'] as int,
    paid: j['paid'] as int,
    remaining: j['remaining'] as int,
    status: parseInvoiceStatus(j['status']),
  );
}

class CardInfo {
  CardInfo({
    required this.id,
    required this.name,
    required this.closingDay,
    required this.dueDay,
    required this.closingDayInNext,
    required this.paymentAccountId,
    required this.currentInvoice,
    required this.limitUsed,
    required this.archived,
    this.limit,
    this.limitAvailable,
    this.color,
    this.lastDigits,
  });

  final String id;
  final String name;

  /// Últimos 4 dígitos (para reconhecer o cartão nas notificações do banco).
  final String? lastDigits;
  final int? limit;
  final int closingDay;
  final int dueDay;
  final bool closingDayInNext;
  final String paymentAccountId;
  final InvoiceSummary currentInvoice;
  final int limitUsed;
  final int? limitAvailable;
  final bool archived;
  final String? color;

  factory CardInfo.fromJson(Map<String, dynamic> j) => CardInfo(
    id: j['id'] as String,
    name: j['name'] as String,
    limit: j['limit'] as int?,
    closingDay: j['closingDay'] as int,
    dueDay: j['dueDay'] as int,
    closingDayInNext: j['closingDayInNext'] as bool? ?? true,
    paymentAccountId: j['paymentAccountId'] as String,
    currentInvoice: InvoiceSummary.fromJson(j['currentInvoice'] as Map<String, dynamic>),
    limitUsed: j['limitUsed'] as int,
    limitAvailable: j['limitAvailable'] as int?,
    archived: j['archived'] as bool? ?? false,
    color: j['color'] as String?,
    lastDigits: j['lastDigits'] as String?,
  );
}

/// Item de uma fatura (compra ou estorno) ou pagamento.
class InvoiceEntry {
  InvoiceEntry({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.isCredit,
    required this.paid,
    this.category,
    this.installmentNumber,
    this.installmentTotal,
  });

  final String id;
  final String description;
  final int amount;
  final DateTime date;

  /// Estorno (abate da fatura).
  final bool isCredit;
  final bool paid;
  final CategoryRef? category;
  final int? installmentNumber;
  final int? installmentTotal;

  factory InvoiceEntry.fromJson(Map<String, dynamic> j) => InvoiceEntry(
    id: j['id'] as String,
    description: j['description'] as String,
    amount: j['amount'] as int,
    date: parseDate(j['date'] as String),
    isCredit: j['type'] == 'INCOME',
    paid: j['status'] == 'PAID',
    category: CategoryRef.fromJson(j['category']),
    installmentNumber: j['installmentNumber'] as int?,
    installmentTotal: j['installmentTotal'] as int?,
  );
}

/// Total de um mês (histórico do relatório por categoria).
class MonthTotal {
  MonthTotal(this.month, this.total);
  final DateTime month;
  final int total;

  static List<MonthTotal> listFromJson(dynamic j) => [
    for (final m in (j as List? ?? const [])) MonthTotal(parseDate(m['month'] as String), m['total'] as int),
  ];
}

/// Uma linha do relatório por categoria. [id] null = sem categoria.
class CategorySpend {
  CategorySpend({
    required this.id,
    required this.name,
    required this.total,
    required this.count,
    required this.share,
    required this.previous,
    required this.average,
    this.color,
    this.icon,
  });

  final String? id;
  final String name;
  final String? color;
  final String? icon;
  final int total;
  final int count;

  /// Fatia do total (0 a 1).
  final double share;

  /// Período anterior, de mesmo tamanho.
  final int previous;

  /// Média dos 3 períodos anteriores.
  final int average;

  factory CategorySpend.fromJson(Map<String, dynamic> j) => CategorySpend(
    id: j['id'] as String?,
    name: j['name'] as String,
    color: j['color'] as String?,
    icon: j['icon'] as String?,
    total: j['total'] as int,
    count: j['count'] as int,
    share: (j['share'] as num).toDouble(),
    previous: j['previous'] as int,
    average: j['average'] as int,
  );
}

class CategoryReport {
  CategoryReport({
    required this.from,
    required this.to,
    required this.total,
    required this.count,
    required this.previousTotal,
    required this.averageTotal,
    required this.categories,
    required this.history,
  });

  final DateTime from;
  final DateTime to;
  final int total;
  final int count;
  final int previousTotal;
  final int averageTotal;
  final List<CategorySpend> categories;
  final List<MonthTotal> history;

  factory CategoryReport.fromJson(Map<String, dynamic> j) => CategoryReport(
    from: parseDate(j['from'] as String),
    to: parseDate(j['to'] as String),
    total: j['total'] as int,
    count: j['count'] as int,
    previousTotal: j['previousTotal'] as int,
    averageTotal: j['averageTotal'] as int,
    categories: [for (final c in j['categories'] as List) CategorySpend.fromJson(c as Map<String, dynamic>)],
    history: MonthTotal.listFromJson(j['history']),
  );
}

/// Lançamento no detalhe de uma categoria: [amount] negativo = estorno (abate).
class CategoryEntry {
  CategoryEntry({required this.tx, required this.date, required this.amount});
  final TxItem tx;

  /// Dia em que conta no relatório (compra ou vencimento da fatura).
  final DateTime date;
  final int amount;
}

class CategoryDetail {
  CategoryDetail({required this.total, required this.history, required this.items});
  final int total;
  final List<MonthTotal> history;
  final List<CategoryEntry> items;

  factory CategoryDetail.fromJson(Map<String, dynamic> j) => CategoryDetail(
    total: j['total'] as int,
    history: MonthTotal.listFromJson(j['history']),
    items: [
      for (final i in j['items'] as List)
        CategoryEntry(
          tx: TxItem.fromJson(i as Map<String, dynamic>),
          date: parseDate(i['reportDate'] as String),
          amount: i['reportAmount'] as int,
        ),
    ],
  );
}

/// Previsão no relatório de previsões, com os lançamentos reais que a abateram.
class ForecastEntry {
  ForecastEntry({required this.tx, required this.fixed, required this.abatements});
  final TxItem tx;

  /// Gerada por um fixo (repete todo mês).
  final bool fixed;
  final List<TxItem> abatements;

  ForecastInfo get info => tx.forecast!;
}

class ForecastTotals {
  const ForecastTotals({
    required this.planned,
    required this.abated,
    required this.remaining,
    required this.effective,
    required this.count,
  });
  final int planned;
  final int abated;
  final int remaining;
  final int effective;
  final int count;

  factory ForecastTotals.fromJson(dynamic j) => ForecastTotals(
    planned: j['planned'] as int,
    abated: j['abated'] as int,
    remaining: j['remaining'] as int,
    effective: j['effective'] as int,
    count: j['count'] as int,
  );
}

class ForecastReport {
  ForecastReport({
    required this.from,
    required this.to,
    required this.expense,
    required this.income,
    required this.items,
  });
  final DateTime from;
  final DateTime to;
  final ForecastTotals expense;
  final ForecastTotals income;
  final List<ForecastEntry> items;

  factory ForecastReport.fromJson(Map<String, dynamic> j) => ForecastReport(
    from: parseDate(j['from'] as String),
    to: parseDate(j['to'] as String),
    expense: ForecastTotals.fromJson(j['totals']['EXPENSE']),
    income: ForecastTotals.fromJson(j['totals']['INCOME']),
    items: [
      for (final i in j['items'] as List)
        ForecastEntry(
          tx: TxItem.fromJson(i as Map<String, dynamic>),
          fixed: i['fixed'] as bool? ?? false,
          abatements: [
            for (final a in (i['abatements'] as List? ?? const [])) TxItem.fromJson(a as Map<String, dynamic>),
          ],
        ),
    ],
  );
}

class CashflowBucket {
  CashflowBucket({
    required this.start,
    required this.end,
    required this.income,
    required this.expense,
    required this.transfersIn,
    required this.transfersOut,
    required this.net,
    required this.opening,
    required this.closing,
  });

  final DateTime start;
  final DateTime end;
  final int income;
  final int expense;
  final int transfersIn;
  final int transfersOut;
  final int net;
  final int opening;
  final int closing;

  factory CashflowBucket.fromJson(Map<String, dynamic> j) => CashflowBucket(
    start: parseDate(j['start'] as String),
    end: parseDate(j['end'] as String),
    income: j['income'] as int,
    expense: j['expense'] as int,
    transfersIn: j['transfersIn'] as int,
    transfersOut: j['transfersOut'] as int,
    net: j['net'] as int,
    opening: j['opening'] as int,
    closing: j['closing'] as int,
  );
}

class CashflowReport {
  CashflowReport({
    required this.from,
    required this.to,
    required this.openingBalance,
    required this.closingBalance,
    required this.income,
    required this.expense,
    required this.transfersIn,
    required this.transfersOut,
    required this.net,
    required this.buckets,
  });

  final DateTime from;
  final DateTime to;
  final int openingBalance;
  final int closingBalance;
  final int income;
  final int expense;
  final int transfersIn;
  final int transfersOut;
  final int net;
  final List<CashflowBucket> buckets;

  factory CashflowReport.fromJson(Map<String, dynamic> j) {
    final t = j['totals'] as Map<String, dynamic>;
    return CashflowReport(
      from: parseDate(j['from'] as String),
      to: parseDate(j['to'] as String),
      openingBalance: j['openingBalance'] as int,
      closingBalance: j['closingBalance'] as int,
      income: t['income'] as int,
      expense: t['expense'] as int,
      transfersIn: t['transfersIn'] as int,
      transfersOut: t['transfersOut'] as int,
      net: t['net'] as int,
      buckets: [for (final b in j['buckets'] as List) CashflowBucket.fromJson(b as Map<String, dynamic>)],
    );
  }
}

/// Totais das contrapartidas de um tipo: pendente (falta receber/pagar) e já quitado.
class CounterpartTotals {
  const CounterpartTotals({required this.pending, required this.settled, required this.count});
  final int pending;
  final int settled;
  final int count;

  int get total => pending + settled;

  factory CounterpartTotals.fromJson(dynamic j) => CounterpartTotals(
    pending: j['pending'] as int? ?? 0,
    settled: j['settled'] as int? ?? 0,
    count: j['count'] as int? ?? 0,
  );
}

/// Contrapartida e o lançamento de origem que ela zera.
class CounterpartEntry {
  CounterpartEntry({required this.tx, required this.origin});

  /// A contrapartida ("Compensação de: ...").
  final TxItem tx;
  final TxItem origin;

  /// Receita = alguém vai te pagar de volta; despesa = você vai devolver.
  bool get toReceive => tx.type == TxType.income;
}

class CounterpartReport {
  CounterpartReport({
    required this.from,
    required this.to,
    required this.income,
    required this.expense,
    required this.items,
  });
  final DateTime from;
  final DateTime to;

  /// A receber de volta (origem é despesa).
  final CounterpartTotals income;

  /// A devolver (origem é receita).
  final CounterpartTotals expense;
  final List<CounterpartEntry> items;

  factory CounterpartReport.fromJson(Map<String, dynamic> j) => CounterpartReport(
    from: parseDate(j['from'] as String),
    to: parseDate(j['to'] as String),
    income: CounterpartTotals.fromJson(j['totals']['INCOME']),
    expense: CounterpartTotals.fromJson(j['totals']['EXPENSE']),
    items: [
      for (final i in j['items'] as List)
        CounterpartEntry(
          tx: TxItem.fromJson(i as Map<String, dynamic>),
          origin: TxItem.fromJson(i['origin'] as Map<String, dynamic>),
        ),
    ],
  );
}

/// Fatura no painel do mês.
class DashboardInvoice {
  DashboardInvoice({
    required this.id,
    required this.cardId,
    required this.cardName,
    required this.dueDate,
    required this.total,
    required this.paid,
    required this.remaining,
    required this.status,
    required this.forecastTotal,
  });
  final String id;
  final String cardId;
  final String cardName;
  final DateTime dueDate;
  final int total;
  final int paid;
  final int remaining;
  final InvoiceStatus status;
  final int forecastTotal;

  factory DashboardInvoice.fromJson(Map<String, dynamic> j) => DashboardInvoice(
    id: j['id'] as String,
    cardId: j['cardId'] as String,
    cardName: j['cardName'] as String,
    dueDate: parseDate(j['dueDate'] as String),
    total: j['total'] as int,
    paid: j['paid'] as int,
    remaining: j['remaining'] as int,
    status: parseInvoiceStatus(j['status']),
    forecastTotal: j['forecastTotal'] as int? ?? 0,
  );
}

class DashboardCard {
  DashboardCard({required this.id, required this.name, required this.limit, required this.limitUsed, this.color});
  final String id;
  final String name;
  final String? color;
  final int? limit;
  final int limitUsed;

  factory DashboardCard.fromJson(Map<String, dynamic> j) => DashboardCard(
    id: j['id'] as String,
    name: j['name'] as String,
    color: j['color'] as String?,
    limit: j['limit'] as int?,
    limitUsed: j['limitUsed'] as int? ?? 0,
  );
}

/// Valor previsto (pagos + pendentes) e realizado (só pagos).
class PlannedActual {
  const PlannedActual({required this.projected, required this.realized});
  final int projected;
  final int realized;

  factory PlannedActual.fromJson(dynamic j) =>
      PlannedActual(projected: j['projected'] as int, realized: j['realized'] as int);
}

/// Painel do mês (aba Início).
class Dashboard {
  Dashboard({
    required this.from,
    required this.to,
    required this.today,
    required this.opening,
    required this.todayBalance,
    required this.monthEnd,
    required this.income,
    required this.expense,
    required this.net,
    required this.topExpenses,
    required this.topIncomes,
    required this.invoices,
    required this.cards,
    required this.forecastExpense,
    required this.forecastIncome,
    required this.counterpartIncome,
    required this.counterpartExpense,
  });

  final DateTime from;
  final DateTime to;
  final DateTime today;
  final Balance opening;
  final Balance todayBalance;
  final Balance monthEnd;
  final PlannedActual income;
  final PlannedActual expense;
  final PlannedActual net;
  final List<CategorySpend> topExpenses;
  final List<CategorySpend> topIncomes;
  final List<DashboardInvoice> invoices;
  final List<DashboardCard> cards;
  final ForecastTotals forecastExpense;
  final ForecastTotals forecastIncome;
  final CounterpartTotals counterpartIncome;
  final CounterpartTotals counterpartExpense;

  bool get isCurrentMonth => !today.isBefore(from) && !today.isAfter(to);

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    ForecastTotals ft(dynamic f) => ForecastTotals.fromJson(f);
    List<CategorySpend> cats(dynamic l) => [
      for (final c in (l as List? ?? const [])) CategorySpend.fromJson(c as Map<String, dynamic>),
    ];
    return Dashboard(
      from: parseDate(j['from'] as String),
      to: parseDate(j['to'] as String),
      today: parseDate(j['today'] as String),
      opening: Balance.fromJson(j['balance']['opening']),
      todayBalance: Balance.fromJson(j['balance']['today']),
      monthEnd: Balance.fromJson(j['balance']['monthEnd']),
      income: PlannedActual.fromJson(j['income']),
      expense: PlannedActual.fromJson(j['expense']),
      net: PlannedActual.fromJson(j['net']),
      topExpenses: cats(j['topExpenses']),
      topIncomes: cats(j['topIncomes']),
      invoices: [for (final i in j['invoices'] as List) DashboardInvoice.fromJson(i as Map<String, dynamic>)],
      cards: [for (final c in j['cards'] as List) DashboardCard.fromJson(c as Map<String, dynamic>)],
      forecastExpense: ft(j['forecasts']['EXPENSE']),
      forecastIncome: ft(j['forecasts']['INCOME']),
      counterpartIncome: CounterpartTotals.fromJson(j['counterparts']['INCOME']),
      counterpartExpense: CounterpartTotals.fromJson(j['counterparts']['EXPENSE']),
    );
  }
}

enum SuggestionStatus { pending, accepted, dismissed, autoPaid, alreadyExists, ignored, error }

SuggestionStatus parseSuggestionStatus(dynamic s) => switch (s) {
  'ACCEPTED' => SuggestionStatus.accepted,
  'DISMISSED' => SuggestionStatus.dismissed,
  'AUTO_PAID' => SuggestionStatus.autoPaid,
  'ALREADY_EXISTS' => SuggestionStatus.alreadyExists,
  'IGNORED' => SuggestionStatus.ignored,
  'ERROR' => SuggestionStatus.error,
  _ => SuggestionStatus.pending,
};

/// Notificação de banco lida no celular e interpretada pela IA.
class SuggestionItem {
  SuggestionItem({
    required this.id,
    required this.status,
    required this.app,
    required this.text,
    required this.postedAt,
    this.reason,
    this.appName,
    this.title,
    this.type,
    this.channel,
    this.amount,
    this.date,
    this.merchant,
    this.description,
    this.accountId,
    this.cardId,
    this.categoryId,
    this.installments,
    this.confidence,
    this.transactionId,
    this.transactionDescription,
  });

  final String id;
  final SuggestionStatus status;
  final String? reason;
  final String app;
  final String? appName;
  final String? title;
  final String text;
  final DateTime postedAt;
  final TxType? type;
  final String? channel;
  final int? amount;
  final DateTime? date;
  final String? merchant;
  final String? description;
  final String? accountId;
  final String? cardId;
  final String? categoryId;
  final int? installments;
  final double? confidence;

  /// Lançamento ligado (o que recebeu baixa, o que já existia, ou o criado ao aceitar).
  final String? transactionId;
  final String? transactionDescription;

  factory SuggestionItem.fromJson(Map<String, dynamic> j) {
    final t = j['transaction'];
    return SuggestionItem(
      id: j['id'] as String,
      status: parseSuggestionStatus(j['status']),
      reason: j['reason'] as String?,
      app: j['app'] as String,
      appName: j['appName'] as String?,
      title: j['title'] as String?,
      text: j['text'] as String,
      postedAt: DateTime.parse(j['postedAt'] as String).toLocal(),
      type: switch (j['type']) {
        'INCOME' => TxType.income,
        'EXPENSE' => TxType.expense,
        'TRANSFER' => TxType.transfer,
        _ => null,
      },
      channel: j['channel'] as String?,
      amount: j['amount'] as int?,
      date: j['date'] == null ? null : parseDate(j['date'] as String),
      merchant: j['merchant'] as String?,
      description: j['description'] as String?,
      accountId: j['accountId'] as String?,
      cardId: j['cardId'] as String?,
      categoryId: j['categoryId'] as String?,
      installments: j['installments'] as int?,
      confidence: (j['confidence'] as num?)?.toDouble(),
      transactionId: t == null ? null : t['id'] as String?,
      transactionDescription: t == null ? null : t['description'] as String?,
    );
  }
}
