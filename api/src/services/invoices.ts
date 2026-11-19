import type { CreditCard } from '@prisma/client';
import { prisma, type Db } from '../db';
import { invoicePeriodForPurchase, invoiceTotals, type InvoicePeriod } from '../domain/invoice';
import { fromDate, toDate, today as todayFn, type DateStr } from '../lib/dates';
import { HttpError } from '../lib/http';
import { ownedAccount, ownedInvoice } from './owned';

export async function getOrCreateInvoice(db: Db, cardId: string, period: InvoicePeriod) {
  return db.invoice.upsert({
    where: { cardId_refMonth: { cardId, refMonth: toDate(period.refMonth) } },
    create: {
      cardId,
      refMonth: toDate(period.refMonth),
      closingDate: toDate(period.closingDate),
      dueDate: toDate(period.dueDate),
    },
    update: {},
  });
}

/** Id da fatura onde entra uma compra no cartão feita em `date`. */
export async function invoiceIdForPurchase(
  db: Db,
  card: CreditCard,
  date: DateStr,
  offsetMonths = 0,
): Promise<string> {
  const inv = await getOrCreateInvoice(db, card.id, invoicePeriodForPurchase(date, card, offsetMonths));
  return inv.id;
}

export function refLabel(refMonth: Date): string {
  const s = fromDate(refMonth);
  return `${s.slice(5, 7)}/${s.slice(0, 4)}`;
}

/** Cria o lançamento de pagamento (total ou parcial) de uma fatura. */
export async function payInvoice(
  userId: string,
  invoiceId: string,
  input: { accountId?: string; amount?: number; date?: DateStr; status?: 'PENDING' | 'PAID' },
) {
  const invoice = await ownedInvoice(userId, invoiceId);
  const [items, payments] = await Promise.all([
    prisma.transaction.findMany({ where: { invoiceId, isForecast: false }, select: { type: true, amount: true } }),
    prisma.transaction.findMany({ where: { paysInvoiceId: invoiceId }, select: { amount: true } }),
  ]);
  const { remaining } = invoiceTotals(items, payments);
  const amount = input.amount ?? remaining;
  if (amount <= 0) throw new HttpError(400, 'Esta fatura não tem valor a pagar');

  const accountId = input.accountId ?? invoice.card.paymentAccountId;
  await ownedAccount(userId, accountId);
  const date = input.date ?? todayFn();
  const status = input.status ?? 'PAID';

  return prisma.transaction.create({
    data: {
      userId,
      type: 'EXPENSE',
      status,
      description: `Pagamento fatura ${invoice.card.name} ${refLabel(invoice.refMonth)}`,
      amount,
      date: toDate(date),
      paidAt: status === 'PAID' ? toDate(date) : null,
      accountId,
      paysInvoiceId: invoiceId,
    },
  });
}
