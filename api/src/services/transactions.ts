import { randomUUID } from 'node:crypto';
import type { CreditCard, Prisma, Transaction } from '@prisma/client';
import { z } from 'zod';
import { prisma, type Db } from '../db';
import { addDays, addMonths, maxDate, toDate, type DateStr } from '../lib/dates';
import { dateStr, HttpError, id, money } from '../lib/http';
import {
  checkCanHaveCounterpart,
  createCounterpart,
  syncFromCounterpart,
  syncFromOrigin,
  syncGroupAmounts,
} from './counterpart';
import { checkForecastLink } from './forecasts';
import { invoiceIdForPurchase } from './invoices';
import { ownedAccount, ownedCard, ownedCategory, ownedTransaction } from './owned';
import { generateRecurrence, horizon } from './recurrence';

const txType = z.enum(['INCOME', 'EXPENSE', 'TRANSFER']);
const txStatus = z.enum(['PENDING', 'PAID']);

export const createTxSchema = z
  .object({
    type: txType,
    description: z.string().trim().min(1).max(200),
    /** Centavos. Com parcelas, é o valor total ou de cada parcela (ver installments.amountIs). */
    amount: money,
    date: dateStr,
    status: txStatus.optional(),
    categoryId: id.nullish(),
    accountId: id.nullish(),
    toAccountId: id.nullish(),
    cardId: id.nullish(),
    notes: z.string().max(1000).nullish(),
    /** Previsão: valor estimado, abatido depois pelos lançamentos reais. */
    isForecast: z.boolean().optional(),
    /** Lançamento real que abate uma previsão aberta. */
    forecastId: id.nullish(),
    /** Gera a contrapartida (tipo oposto, mesmo valor) ligada a cada lançamento criado. */
    counterpart: z.boolean().optional(),
    installments: z
      .object({
        total: z.number().int().min(2).max(360),
        amountIs: z.enum(['total', 'each']).default('total'),
      })
      .optional(),
    recurrence: z
      .object({
        frequency: z.enum(['WEEKLY', 'MONTHLY', 'YEARLY']),
        interval: z.number().int().min(1).max(12).default(1),
        endDate: dateStr.optional(),
      })
      .optional(),
  })
  .superRefine((v, ctx) => {
    const issue = (message: string, path: string) => ctx.addIssue({ code: 'custom', message, path: [path] });
    if (v.type === 'TRANSFER') {
      if (!v.accountId) issue('Informe a conta de origem', 'accountId');
      if (!v.toAccountId) issue('Informe a conta de destino', 'toAccountId');
      if (v.accountId && v.accountId === v.toAccountId) issue('Origem e destino iguais', 'toAccountId');
      if (v.cardId) issue('Transferência não usa cartão', 'cardId');
    } else {
      if (!!v.accountId === !!v.cardId) issue('Informe uma conta OU um cartão', 'accountId');
      if (v.toAccountId) issue('Só transferências têm conta de destino', 'toAccountId');
    }
    if (v.installments && v.recurrence) issue('Escolha parcelado OU fixo', 'recurrence');
    if (v.recurrence?.endDate && v.recurrence.endDate < v.date) issue('Fim antes do início', 'recurrence');
    if (v.isForecast) {
      if (v.type === 'TRANSFER') issue('Transferência não pode ser previsão', 'isForecast');
      if (v.installments) issue('Previsão não pode ser parcelada', 'installments');
      if (v.forecastId) issue('Uma previsão não abate outra', 'forecastId');
    }
    if (v.forecastId && (v.installments || v.recurrence)) {
      issue('Só lançamentos avulsos abatem previsões', 'forecastId');
    }
    if (v.counterpart) {
      if (v.type === 'TRANSFER') issue('Transferência não tem contrapartida', 'counterpart');
      if (v.isForecast) issue('Previsão não tem contrapartida', 'counterpart');
    }
  });

export type CreateTxInput = z.infer<typeof createTxSchema>;

async function checkRefs(
  userId: string,
  v: { type: string; categoryId?: string | null; accountId?: string | null; toAccountId?: string | null; cardId?: string | null },
): Promise<CreditCard | null> {
  if (v.accountId) await ownedAccount(userId, v.accountId);
  if (v.toAccountId) await ownedAccount(userId, v.toAccountId);
  if (v.categoryId) {
    const cat = await ownedCategory(userId, v.categoryId);
    if (v.type !== 'TRANSFER' && cat.kind !== v.type) {
      throw new HttpError(400, 'Categoria não combina com o tipo do lançamento');
    }
  }
  return v.cardId ? ownedCard(userId, v.cardId) : null;
}

/** Divide um total em N parcelas inteiras; a diferença de centavos vai na primeira. */
export function splitInstallments(total: number, n: number): number[] {
  const base = Math.floor(total / n);
  const out = Array.from({ length: n }, () => base);
  out[0] += total - base * n;
  return out;
}

/** Cria um lançamento simples, parcelado ou fixo. Retorna os lançamentos criados. */
export async function createTransaction(userId: string, input: CreateTxInput, today: DateStr) {
  const card = await checkRefs(userId, input);
  if (input.forecastId) await checkForecastLink(userId, input.forecastId, input.type);
  const isForecast = input.isForecast ?? false;
  const forecastFields = {
    isForecast,
    forecastState: isForecast ? ('OPEN' as const) : null,
    forecastId: isForecast ? null : (input.forecastId ?? null),
  };

  const common = {
    userId,
    type: input.type,
    description: input.description,
    categoryId: input.categoryId ?? null,
    accountId: card ? null : (input.accountId ?? null),
    toAccountId: input.toAccountId ?? null,
    cardId: card?.id ?? null,
    notes: input.notes ?? null,
  };
  // Padrão: o que já aconteceu está pago; o futuro fica pendente.
  const defaultStatus = (d: DateStr): 'PAID' | 'PENDING' => (d <= today ? 'PAID' : 'PENDING');

  return prisma.$transaction(async (tx) => {
    const created = await createRows(tx);
    if (input.counterpart && !input.recurrence) {
      // Fixos geram a contrapartida junto de cada ocorrência (generateRecurrence).
      for (const t of created) await createCounterpart(tx, t, today);
    }
    return created;
  });

  async function createRows(tx: Db): Promise<Transaction[]> {
    if (input.recurrence) {
      const rec = await tx.recurrence.create({
        data: {
          ...common,
          amount: input.amount,
          frequency: input.recurrence.frequency,
          interval: input.recurrence.interval,
          startDate: toDate(input.date),
          endDate: input.recurrence.endDate ? toDate(input.recurrence.endDate) : null,
          generatedUntil: toDate(addDays(input.date, -1)),
          isForecast,
          withCounterpart: input.counterpart ?? false,
        },
      });
      await generateRecurrence(tx, rec, maxDate(horizon(today), input.date));
      if (isForecast) {
        // Ocorrências de previsão que já passaram nascem expiradas.
        await tx.transaction.updateMany({
          where: { recurrenceId: rec.id, date: { lt: toDate(today) } },
          data: { forecastState: 'EXPIRED' },
        });
      } else if (!card && (input.status ?? 'PENDING') === 'PAID') {
        // Ocorrências que já passaram entram como pagas.
        await tx.transaction.updateMany({
          where: { recurrenceId: rec.id, date: { lte: toDate(today) } },
          data: { status: 'PAID', paidAt: toDate(today) },
        });
      }
      return tx.transaction.findMany({ where: { recurrenceId: rec.id }, orderBy: { date: 'asc' } });
    }

    if (input.installments) {
      const n = input.installments.total;
      const amounts =
        input.installments.amountIs === 'each'
          ? Array.from({ length: n }, () => input.amount)
          : splitInstallments(input.amount, n);
      if (amounts.some((a) => a <= 0)) throw new HttpError(400, 'Valor pequeno demais para tantas parcelas');
      const groupId = randomUUID();
      const created: Transaction[] = [];
      for (let i = 0; i < n; i++) {
        const date = addMonths(input.date, i);
        const status = card ? 'PAID' : i === 0 ? (input.status ?? defaultStatus(date)) : 'PENDING';
        created.push(
          await tx.transaction.create({
            data: {
              ...common,
              amount: amounts[i],
              date: toDate(date),
              status,
              paidAt: status === 'PAID' && !card ? toDate(date) : null,
              // Parcela i vai para a i-ésima fatura a partir da fatura da compra.
              invoiceId: card ? await invoiceIdForPurchase(tx, card, input.date, i) : null,
              installmentGroupId: groupId,
              installmentNumber: i + 1,
              installmentTotal: n,
            },
          }),
        );
      }
      return created;
    }

    // Previsão nunca está paga; o que conta como realizado são os lançamentos que a abatem.
    const status = isForecast ? 'PENDING' : card ? 'PAID' : (input.status ?? defaultStatus(input.date));
    return [
      await tx.transaction.create({
        data: {
          ...common,
          ...forecastFields,
          forecastState: isForecast ? (input.date < today ? 'EXPIRED' : 'OPEN') : null,
          amount: input.amount,
          date: toDate(input.date),
          status,
          paidAt: status === 'PAID' && !card ? toDate(input.date) : null,
          invoiceId: card ? await invoiceIdForPurchase(tx, card, input.date) : null,
        },
      }),
    ];
  }
}

export const scopeSchema = z.enum(['one', 'future', 'all']).default('one');
export type Scope = z.infer<typeof scopeSchema>;

export const updateTxSchema = z.object({
  description: z.string().trim().min(1).max(200).optional(),
  amount: money.optional(),
  date: dateStr.optional(),
  status: txStatus.optional(),
  categoryId: id.nullish(),
  accountId: id.optional(),
  toAccountId: id.optional(),
  cardId: id.optional(),
  notes: z.string().max(1000).nullish(),
  /** Lançamento real: previsão que ele abate (null desvincula). */
  forecastId: id.nullish(),
  /** Lançamento de origem: true gera a contrapartida (se ainda não tem); false exclui a que existe. */
  counterpart: z.boolean().optional(),
});
export type UpdateTxInput = z.infer<typeof updateTxSchema>;

/** Filtro do grupo (fixo ou parcelado) a partir do lançamento, conforme o escopo. */
function groupWhere(t: Transaction, scope: Scope): Prisma.TransactionWhereInput | null {
  if (scope === 'one') return null;
  if (t.recurrenceId) {
    return scope === 'all'
      ? { recurrenceId: t.recurrenceId }
      : { recurrenceId: t.recurrenceId, date: { gte: t.date } };
  }
  if (t.installmentGroupId) {
    return scope === 'all'
      ? { installmentGroupId: t.installmentGroupId }
      : { installmentGroupId: t.installmentGroupId, installmentNumber: { gte: t.installmentNumber ?? 1 } };
  }
  return null;
}

/**
 * Edita um lançamento.
 * - scope 'one': qualquer campo deste lançamento.
 * - scope 'future'/'all' (fixos e parcelados): descrição, valor, categoria e observação
 *   deste e dos próximos / de todos; nos fixos, também muda o modelo das próximas gerações.
 */
export async function updateTransaction(userId: string, txId: string, input: UpdateTxInput, scope: Scope, today: DateStr) {
  const current = await ownedTransaction(userId, txId);
  const where = groupWhere(current, scope);

  if (where) {
    if (input.categoryId) await checkRefs(userId, { type: current.type, categoryId: input.categoryId });
    const data = {
      description: input.description,
      amount: input.amount,
      categoryId: input.categoryId,
      notes: input.notes,
    };
    await prisma.$transaction(async (tx) => {
      const affected = await tx.transaction.findMany({ where: { ...where, userId }, select: { id: true } });
      await tx.transaction.updateMany({ where: { ...where, userId }, data });
      await syncGroupAmounts(
        tx,
        affected.map((a) => a.id),
        input.amount,
      );
      if (current.recurrenceId) {
        await tx.recurrence.update({ where: { id: current.recurrenceId }, data });
      }
    });
    return ownedTransaction(userId, txId);
  }

  if (current.paysInvoiceId && (input.cardId || input.toAccountId)) {
    throw new HttpError(400, 'Pagamento de fatura só pode mudar de conta');
  }
  if (current.counterpartOfId && (input.cardId || input.counterpart !== undefined)) {
    throw new HttpError(400, 'A contrapartida fica sempre em uma conta');
  }

  const merged = {
    type: current.type,
    categoryId: input.categoryId === undefined ? current.categoryId : input.categoryId,
    accountId: input.cardId ? null : (input.accountId ?? current.accountId),
    toAccountId: input.toAccountId ?? current.toAccountId,
    cardId: input.accountId ? null : (input.cardId ?? current.cardId),
  };
  if (merged.type === 'TRANSFER' && merged.accountId === merged.toAccountId) {
    throw new HttpError(400, 'Origem e destino iguais');
  }
  const card = await checkRefs(userId, merged);
  const date = input.date ?? current.date.toISOString().slice(0, 10);
  const status = current.isForecast ? 'PENDING' : card ? 'PAID' : (input.status ?? current.status);

  let forecastId = current.forecastId;
  if (!current.isForecast && input.forecastId !== undefined && input.forecastId !== current.forecastId) {
    if (input.forecastId) await checkForecastLink(userId, input.forecastId, current.type);
    forecastId = input.forecastId ?? null;
  }
  // Mudar a data de uma previsão reabre (data futura) ou expira (data passada); encerrada continua encerrada.
  const forecastState =
    current.isForecast && current.forecastState !== 'CLOSED' ? (date < today ? 'EXPIRED' : 'OPEN') : current.forecastState;

  return prisma.$transaction(async (tx) => {
    const updated = await tx.transaction.update({
      where: { id: txId },
      data: {
        description: input.description,
        amount: input.amount,
        notes: input.notes,
        date: toDate(date),
        status,
        paidAt:
          status === 'PAID' && !card ? (current.paidAt ?? toDate(minToday(date, today))) : null,
        categoryId: merged.categoryId,
        accountId: merged.accountId,
        toAccountId: merged.toAccountId,
        cardId: merged.cardId,
        forecastId,
        forecastState,
        // Só recalcula a fatura se mudou a data ou o cartão (preserva a fatura das parcelas).
        invoiceId: !card
          ? null
          : input.date || card.id !== current.cardId || !current.invoiceId
            ? await invoiceIdForPurchase(tx, card, date)
            : current.invoiceId,
      },
    });

    if (updated.counterpartOfId) {
      await syncFromCounterpart(tx, current, updated);
    } else if (input.counterpart === false) {
      await tx.transaction.deleteMany({ where: { counterpartOfId: updated.id } });
    } else {
      await syncFromOrigin(tx, current, updated, today);
      if (input.counterpart && !(await tx.transaction.findUnique({ where: { counterpartOfId: updated.id } }))) {
        checkCanHaveCounterpart(updated);
        await createCounterpart(tx, updated, today);
      }
    }
    return updated;
  });
}

const minToday = (date: DateStr, today: DateStr) => (date < today ? date : today);

export async function setTransactionStatus(userId: string, txId: string, status: 'PENDING' | 'PAID', today: DateStr) {
  const current = await ownedTransaction(userId, txId);
  if (current.cardId) throw new HttpError(400, 'Compras no cartão são pagas pela fatura');
  if (current.isForecast) throw new HttpError(400, 'Previsão não é paga: lance o valor real abatendo dela');
  return prisma.transaction.update({
    where: { id: txId },
    data: { status, paidAt: status === 'PAID' ? toDate(today) : null },
  });
}

/** Exclui um lançamento; nos fixos/parcelados pode excluir os próximos ou todos. */
export async function deleteTransaction(userId: string, txId: string, scope: Scope): Promise<number> {
  const current = await ownedTransaction(userId, txId);
  if (current.counterpartOfId) {
    // Excluir a contrapartida exclui a origem; a contrapartida vai junto (cascade).
    await prisma.transaction.delete({ where: { id: current.counterpartOfId } });
    return 2;
  }
  const where = groupWhere(current, scope);
  if (!where) {
    // A contrapartida, se houver, é excluída junto (cascade).
    await prisma.transaction.delete({ where: { id: txId } });
    return 1;
  }
  return prisma.$transaction(async (tx) => {
    const { count } = await tx.transaction.deleteMany({ where: { ...where, userId } });
    if (current.recurrenceId) {
      if (scope === 'all') {
        await tx.recurrence.delete({ where: { id: current.recurrenceId } });
      } else {
        // Encerra o fixo no dia anterior para não gerar de novo.
        await tx.recurrence.update({
          where: { id: current.recurrenceId },
          data: { endDate: new Date(current.date.getTime() - 86_400_000) },
        });
      }
    }
    return count;
  });
}
