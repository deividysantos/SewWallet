import { addDays, endOfMonth, endOfWeek, maxDate, minDate, type DateStr } from '../lib/dates';

/** Dados mínimos de um lançamento para calcular saldos. */
export interface LedgerTx {
  id: string;
  type: 'INCOME' | 'EXPENSE' | 'TRANSFER';
  status: 'PENDING' | 'PAID';
  amount: number;
  date: DateStr;
  accountId: string | null;
  toAccountId: string | null;
  cardId: string | null;
  categoryId: string | null;
}

/** Fatura com o valor que ainda falta pagar (ou agendar). */
export interface LedgerInvoice {
  id: string;
  paymentAccountId: string;
  dueDate: DateStr;
  remaining: number;
}

export type CashEventKind = 'INCOME' | 'EXPENSE' | 'TRANSFER_IN' | 'TRANSFER_OUT';

/** Movimento de dinheiro em uma conta, na data em que afeta o saldo. */
export interface CashEvent {
  date: DateStr;
  accountId: string;
  delta: number;
  paid: boolean;
  kind: CashEventKind;
  /** Transferência entre duas contas que estão no filtro (não é entrada nem saída de fato). */
  internal: boolean;
  sourceType: 'transaction' | 'invoice';
  sourceId: string;
  categoryId: string | null;
}

/**
 * Converte lançamentos e faturas em movimentos de conta.
 * - Compras no cartão não mexem na conta: entram pela fatura, no vencimento.
 * - Pendentes atrasados contam como se fossem pagos hoje (o dinheiro ainda vai sair).
 * - `accountFilter` nulo = todas as contas.
 */
export function buildCashEvents(
  txs: LedgerTx[],
  invoices: LedgerInvoice[],
  today: DateStr,
  accountFilter: Set<string> | null,
): CashEvent[] {
  const included = (id: string | null): id is string =>
    id !== null && (accountFilter === null || accountFilter.has(id));
  const events: CashEvent[] = [];

  for (const tx of txs) {
    if (tx.cardId) continue;
    const paid = tx.status === 'PAID';
    const date = paid ? tx.date : maxDate(tx.date, today);
    const base = { date, paid, sourceType: 'transaction' as const, sourceId: tx.id, categoryId: tx.categoryId };

    if (tx.type === 'INCOME' && included(tx.accountId)) {
      events.push({ ...base, accountId: tx.accountId, delta: tx.amount, kind: 'INCOME', internal: false });
    } else if (tx.type === 'EXPENSE' && included(tx.accountId)) {
      events.push({ ...base, accountId: tx.accountId, delta: -tx.amount, kind: 'EXPENSE', internal: false });
    } else if (tx.type === 'TRANSFER') {
      const fromIn = included(tx.accountId);
      const toIn = included(tx.toAccountId);
      const internal = fromIn && toIn;
      if (fromIn) {
        events.push({ ...base, accountId: tx.accountId!, delta: -tx.amount, kind: 'TRANSFER_OUT', internal });
      }
      if (toIn) {
        events.push({ ...base, accountId: tx.toAccountId!, delta: tx.amount, kind: 'TRANSFER_IN', internal });
      }
    }
  }

  for (const inv of invoices) {
    if (inv.remaining <= 0 || !included(inv.paymentAccountId)) continue;
    events.push({
      date: maxDate(inv.dueDate, today),
      accountId: inv.paymentAccountId,
      delta: -inv.remaining,
      paid: false,
      kind: 'EXPENSE',
      internal: false,
      sourceType: 'invoice',
      sourceId: inv.id,
      categoryId: null,
    });
  }

  return events.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
}

export interface DayBalance {
  /** Só o que já foi pago. */
  realized: number;
  /** Pagos + pendentes. */
  projected: number;
}

/** Saldo no FINAL de cada dia pedido. `days` precisa estar em ordem crescente. */
export function dailyBalances(
  events: CashEvent[],
  opening: number,
  days: DateStr[],
): Map<DateStr, DayBalance> {
  const out = new Map<DateStr, DayBalance>();
  let i = 0;
  let realized = opening;
  let projected = opening;
  for (const day of days) {
    while (i < events.length && events[i].date <= day) {
      projected += events[i].delta;
      if (events[i].paid) realized += events[i].delta;
      i++;
    }
    out.set(day, { realized, projected });
  }
  return out;
}

export type Granularity = 'day' | 'week' | 'month';
export type CashflowMode = 'period' | 'cumulative';
export type Basis = 'projected' | 'realized';

export interface CashflowBucket {
  start: DateStr;
  end: DateStr;
  income: number;
  expense: number;
  transfersIn: number;
  transfersOut: number;
  net: number;
  opening: number;
  closing: number;
}

export interface CashflowReport {
  mode: CashflowMode;
  basis: Basis;
  granularity: Granularity;
  from: DateStr;
  to: DateStr;
  openingBalance: number;
  closingBalance: number;
  totals: { income: number; expense: number; transfersIn: number; transfersOut: number; net: number };
  buckets: CashflowBucket[];
}

function bucketRanges(from: DateStr, to: DateStr, granularity: Granularity): [DateStr, DateStr][] {
  const ranges: [DateStr, DateStr][] = [];
  let cursor = from;
  while (cursor <= to) {
    const naturalEnd =
      granularity === 'day' ? cursor : granularity === 'week' ? endOfWeek(cursor) : endOfMonth(cursor);
    const end = minDate(naturalEnd, to);
    ranges.push([cursor, end]);
    cursor = addDays(end, 1);
  }
  return ranges;
}

/**
 * Fluxo de caixa.
 * - mode 'period': começa do zero e considera só os movimentos do intervalo.
 * - mode 'cumulative': começa com o saldo real acumulado até o dia anterior a `from`.
 * - basis 'realized': só pagos; 'projected': pagos + pendentes.
 */
export function buildCashflowReport(params: {
  events: CashEvent[];
  initialBalance: number;
  from: DateStr;
  to: DateStr;
  granularity: Granularity;
  mode: CashflowMode;
  basis: Basis;
}): CashflowReport {
  const { from, to, granularity, mode, basis } = params;
  const events = params.events.filter((e) => basis === 'projected' || e.paid);

  let opening =
    mode === 'period'
      ? 0
      : params.initialBalance + events.filter((e) => e.date < from).reduce((s, e) => s + e.delta, 0);
  const openingBalance = opening;

  const totals = { income: 0, expense: 0, transfersIn: 0, transfersOut: 0, net: 0 };
  const buckets: CashflowBucket[] = [];
  let i = events.findIndex((e) => e.date >= from);
  if (i < 0) i = events.length;

  for (const [start, end] of bucketRanges(from, to, granularity)) {
    const b: CashflowBucket = {
      start,
      end,
      income: 0,
      expense: 0,
      transfersIn: 0,
      transfersOut: 0,
      net: 0,
      opening,
      closing: opening,
    };
    while (i < events.length && events[i].date <= end) {
      const e = events[i++];
      b.net += e.delta;
      if (e.internal) continue;
      if (e.kind === 'INCOME') b.income += e.delta;
      else if (e.kind === 'EXPENSE') b.expense += -e.delta;
      else if (e.kind === 'TRANSFER_IN') b.transfersIn += e.delta;
      else b.transfersOut += -e.delta;
    }
    b.closing = opening + b.net;
    opening = b.closing;
    totals.income += b.income;
    totals.expense += b.expense;
    totals.transfersIn += b.transfersIn;
    totals.transfersOut += b.transfersOut;
    totals.net += b.net;
    buckets.push(b);
  }

  return {
    mode,
    basis,
    granularity,
    from,
    to,
    openingBalance,
    closingBalance: opening,
    totals,
    buckets,
  };
}
