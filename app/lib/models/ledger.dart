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
  });

  @override
  final String id;
  @override
  final String description;

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
        status: switch (j['status']) {
          'OPEN' => InvoiceStatus.open,
          'PAID' => InvoiceStatus.paid,
          'OVERDUE' => InvoiceStatus.overdue,
          _ => InvoiceStatus.closed,
        },
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

class Account {
  Account({
    required this.id,
    required this.name,
    required this.balance,
    required this.projectedMonthEnd,
    required this.archived,
    this.color,
  });

  final String id;
  final String name;
  final int balance;
  final int projectedMonthEnd;
  final bool archived;
  final String? color;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        name: j['name'] as String,
        balance: j['balance'] as int,
        projectedMonthEnd: j['projectedMonthEnd'] as int,
        archived: j['archived'] as bool? ?? false,
        color: j['color'] as String?,
      );
}
