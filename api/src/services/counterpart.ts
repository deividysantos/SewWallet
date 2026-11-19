import type { Transaction } from '@prisma/client';
import type { Db } from '../db';
import { fromDate, toDate, type DateStr } from '../lib/dates';
import { HttpError } from '../lib/http';

/**
 * Contrapartida: lançamento de tipo oposto que zera o de origem.
 * Ex.: compra de R$ 100 no cartão para um amigo que paga depois → receita de R$ 100 na conta
 * que paga a fatura, no vencimento da fatura. Lançamento em conta → mesma conta e mesma data.
 * Os dois ficam ligados: valor e data andam juntos, e excluir um exclui o outro.
 */

export const COUNTERPART_PREFIX = 'Compensação de: ';

export const counterpartDescription = (origin: string) => `${COUNTERPART_PREFIX}${origin}`.slice(0, 200);

type Origin = Pick<Transaction, 'type' | 'accountId' | 'cardId' | 'invoiceId' | 'date' | 'isForecast' | 'paysInvoiceId'>;

export function checkCanHaveCounterpart(t: Origin & { counterpartOfId?: string | null }) {
  if (t.type === 'TRANSFER') throw new HttpError(400, 'Transferência não tem contrapartida');
  if (t.isForecast) throw new HttpError(400, 'Previsão não tem contrapartida');
  if (t.paysInvoiceId) throw new HttpError(400, 'Pagamento de fatura não tem contrapartida');
  if (t.counterpartOfId) throw new HttpError(400, 'Este lançamento já é uma contrapartida');
}

/** Conta e data da contrapartida: no cartão, a conta que paga a fatura no vencimento. */
export async function counterpartTarget(db: Db, origin: Origin): Promise<{ accountId: string; date: DateStr }> {
  if (origin.cardId) {
    const card = await db.creditCard.findUniqueOrThrow({ where: { id: origin.cardId } });
    const invoice = origin.invoiceId ? await db.invoice.findUnique({ where: { id: origin.invoiceId } }) : null;
    return { accountId: card.paymentAccountId, date: fromDate(invoice?.dueDate ?? origin.date) };
  }
  return { accountId: origin.accountId!, date: fromDate(origin.date) };
}

const statusFor = (date: DateStr, today: DateStr) => (date <= today ? ('PAID' as const) : ('PENDING' as const));

export async function createCounterpart(db: Db, origin: Transaction, today: DateStr): Promise<Transaction> {
  checkCanHaveCounterpart(origin);
  const { accountId, date } = await counterpartTarget(db, origin);
  const status = statusFor(date, today);
  return db.transaction.create({
    data: {
      userId: origin.userId,
      type: origin.type === 'EXPENSE' ? 'INCOME' : 'EXPENSE',
      status,
      paidAt: status === 'PAID' ? toDate(date) : null,
      description: counterpartDescription(origin.description),
      amount: origin.amount,
      date: toDate(date),
      accountId,
      counterpartOfId: origin.id,
    },
  });
}

/**
 * Depois de editar a origem: leva valor e data (e a conta, se a origem mudou de conta/cartão)
 * para a contrapartida. A descrição acompanha enquanto não foi personalizada.
 */
export async function syncFromOrigin(db: Db, before: Transaction, after: Transaction, today: DateStr) {
  const cp = await db.transaction.findUnique({ where: { counterpartOfId: after.id } });
  if (!cp) return;
  const placeChanged =
    before.date.getTime() !== after.date.getTime() ||
    before.cardId !== after.cardId ||
    before.accountId !== after.accountId ||
    before.invoiceId !== after.invoiceId;
  const target = placeChanged ? await counterpartTarget(db, after) : null;
  const descFollows = cp.description === counterpartDescription(before.description);
  const dateChanged = target && target.date !== fromDate(cp.date);
  await db.transaction.update({
    where: { id: cp.id },
    data: {
      amount: after.amount,
      description: descFollows ? counterpartDescription(after.description) : undefined,
      accountId: target?.accountId,
      date: target ? toDate(target.date) : undefined,
      // Movida para o futuro, deixa de estar paga (no passado, mantém o status que tinha).
      ...(target && dateChanged && cp.status === 'PAID' && target.date > today ? { status: 'PENDING', paidAt: null } : {}),
    },
  });
}

/**
 * Depois de editar a contrapartida: leva o valor para a origem; a data também, quando a origem é
 * em conta (no cartão, a data da compra não muda por causa do vencimento).
 */
export async function syncFromCounterpart(db: Db, before: Transaction, after: Transaction) {
  if (!after.counterpartOfId) return;
  const origin = await db.transaction.findUnique({ where: { id: after.counterpartOfId } });
  if (!origin) return;
  const dateChanged = before.date.getTime() !== after.date.getTime();
  await db.transaction.update({
    where: { id: origin.id },
    data: {
      amount: after.amount,
      date: dateChanged && !origin.cardId ? after.date : undefined,
    },
  });
}

/** Edição em grupo (fixos/parcelados): as contrapartidas dos lançamentos alterados acompanham o valor. */
export async function syncGroupAmounts(db: Db, originIds: string[], amount: number | undefined) {
  if (amount === undefined || originIds.length === 0) return;
  await db.transaction.updateMany({ where: { counterpartOfId: { in: originIds } }, data: { amount } });
}
