import { addMonths, makeDate, parts, type DateStr } from '../lib/dates';

export interface CardRules {
  closingDay: number;
  dueDay: number;
  /** true: compra feita no próprio dia do fechamento vai para a próxima fatura. */
  closingDayInNext: boolean;
}

export interface InvoicePeriod {
  /** Primeiro dia do mês em que a fatura fecha. */
  refMonth: DateStr;
  closingDate: DateStr;
  dueDate: DateStr;
}

export type InvoiceStatus = 'OPEN' | 'CLOSED' | 'PAID' | 'OVERDUE';

/** Datas de fechamento e vencimento da fatura que fecha no mês `refMonth`. */
export function invoicePeriodForRef(refMonth: DateStr, card: CardRules): InvoicePeriod {
  const { y, m } = parts(refMonth);
  const closingDate = makeDate(y, m, card.closingDay);
  // Vencimento depois do fechamento no mesmo mês; senão, no mês seguinte.
  const dueDate =
    card.dueDay > card.closingDay ? makeDate(y, m, card.dueDay) : makeDate(y, m + 1, card.dueDay);
  return { refMonth: makeDate(y, m, 1), closingDate, dueDate };
}

/** Mês de referência da fatura em que entra uma compra feita em `date`. */
export function invoiceRefForPurchase(date: DateStr, card: CardRules): DateStr {
  const { y, m, d } = parts(date);
  const closingThisMonth = parts(makeDate(y, m, card.closingDay)).d;
  const goesToNext = d > closingThisMonth || (card.closingDayInNext && d === closingThisMonth);
  return makeDate(y, goesToNext ? m + 1 : m, 1);
}

/**
 * Fatura de uma compra. `offsetMonths` desloca para as faturas seguintes
 * (parcela 2 de uma compra = offset 1).
 */
export function invoicePeriodForPurchase(
  date: DateStr,
  card: CardRules,
  offsetMonths = 0,
): InvoicePeriod {
  const ref = invoiceRefForPurchase(date, card);
  return invoicePeriodForRef(addMonths(ref, offsetMonths), card);
}

export function invoiceStatus(
  period: Pick<InvoicePeriod, 'closingDate' | 'dueDate'>,
  total: number,
  paid: number,
  today: DateStr,
  card: Pick<CardRules, 'closingDayInNext'>,
): InvoiceStatus {
  const closed = card.closingDayInNext ? today >= period.closingDate : today > period.closingDate;
  if (!closed) return 'OPEN';
  if (total - paid <= 0) return 'PAID';
  if (today > period.dueDate) return 'OVERDUE';
  return 'CLOSED';
}

/** Total da fatura (compras menos estornos) e quanto já foi pago/agendado. */
export function invoiceTotals(
  items: { type: string; amount: number }[],
  payments: { amount: number }[],
): { total: number; paid: number; remaining: number } {
  const total = items.reduce((s, i) => s + (i.type === 'INCOME' ? -i.amount : i.amount), 0);
  const paid = payments.reduce((s, p) => s + p.amount, 0);
  return { total, paid, remaining: Math.max(total - paid, 0) };
}
