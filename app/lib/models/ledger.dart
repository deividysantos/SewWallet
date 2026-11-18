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

  factory Balance.fromJson(dynamic j) =>
      Balance(realized: j['realized'] as int, projected: j['projected'] as int);
}

sealed class LedgerItem {
  String get id;
  String get description;
  DateTime get date;

  static LedgerItem fromJson(Map<String, dynamic> j) =>
      j['kind'] == 'invoice' ? InvoiceItem.fromJson(j) : TxItem.fromJson(j);
}

enum TxType { income, expense, transfer }

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
  });

  @override
  final String id;
  final TxType type;
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
  });

  @override
  final String id;
  @override
  final String description;

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
        items: [
          for (final i in j['items'] as List) LedgerItem.fromJson(i as Map<String, dynamic>),
        ],
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
  });

  final String id;
  final String name;
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
        for (final m in (j as List? ?? const []))
          MonthTotal(parseDate(m['month'] as String), m['total'] as int),
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
