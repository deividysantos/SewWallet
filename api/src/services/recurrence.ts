import type { Frequency, Recurrence } from '@prisma/client';
import { prisma, type Db } from '../db';
import { addDays, addMonths, fromDate, minDate, toDate, type DateStr } from '../lib/dates';
import { invoiceIdForPurchase } from './invoices';

/** Quantos meses à frente os lançamentos fixos ficam gerados. */
export const HORIZON_MONTHS = 12;

export function horizon(today: DateStr): DateStr {
  return addMonths(today, HORIZON_MONTHS);
}

/** k-ésima ocorrência (k = 0 é a data inicial). Sempre calculada a partir do início, sem acumular desvios. */
export function occurrenceDate(start: DateStr, frequency: Frequency, interval: number, k: number): DateStr {
  switch (frequency) {
    case 'WEEKLY':
      return addDays(start, 7 * interval * k);
    case 'MONTHLY':
      return addMonths(start, interval * k);
    case 'YEARLY':
      return addMonths(start, 12 * interval * k);
  }
}

export function occurrencesBetween(
  rec: Pick<Recurrence, 'startDate' | 'frequency' | 'interval'>,
  after: DateStr,
  until: DateStr,
): DateStr[] {
  const start = fromDate(rec.startDate);
  const dates: DateStr[] = [];
  for (let k = 0; k < 10_000; k++) {
    const d = occurrenceDate(start, rec.frequency, rec.interval, k);
    if (d > until) break;
    if (d > after) dates.push(d);
  }
  return dates;
}

/** Materializa as ocorrências de uma recorrência até `until`. Retorna quantas criou. */
export async function generateRecurrence(db: Db, rec: Recurrence, until: DateStr): Promise<number> {
  const generatedUntil = fromDate(rec.generatedUntil);
  const target = rec.endDate ? minDate(until, fromDate(rec.endDate)) : until;
  if (target <= generatedUntil) return 0;

  // "Reserva" o intervalo: se outra requisição já gerou, não duplica.
  const claimed = await db.recurrence.updateMany({
    where: { id: rec.id, generatedUntil: rec.generatedUntil },
    data: { generatedUntil: toDate(target) },
  });
  if (claimed.count === 0) return 0;

  const card = rec.cardId ? await db.creditCard.findUnique({ where: { id: rec.cardId } }) : null;
  if (rec.cardId && !card) return 0;
  const categoryId =
    rec.categoryId && (await db.category.findUnique({ where: { id: rec.categoryId } })) ? rec.categoryId : null;

  const dates = occurrencesBetween(rec, generatedUntil, target);
  for (const d of dates) {
    await db.transaction.create({
      data: {
        userId: rec.userId,
        type: rec.type,
        status: card ? 'PAID' : 'PENDING',
        description: rec.description,
        amount: rec.amount,
        date: toDate(d),
        notes: rec.notes,
        categoryId,
        accountId: card ? null : rec.accountId,
        toAccountId: card ? null : rec.toAccountId,
        cardId: card?.id ?? null,
        invoiceId: card ? await invoiceIdForPurchase(db, card, d) : null,
        recurrenceId: rec.id,
      },
    });
  }
  return dates.length;
}

/** Garante que todos os fixos do usuário estão gerados até `until`. */
export async function ensureRecurrences(userId: string, until: DateStr): Promise<void> {
  const recs = await prisma.recurrence.findMany({
    where: { userId, generatedUntil: { lt: toDate(until) } },
  });
  for (const rec of recs) {
    if (rec.endDate && rec.generatedUntil >= rec.endDate) continue;
    await prisma.$transaction((tx) => generateRecurrence(tx, rec, until));
  }
}
