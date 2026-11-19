import { createHash } from 'node:crypto';
import { Prisma, type Suggestion } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../db';
import {
  buildPrompt,
  localDate,
  matchNotification,
  parseAiResult,
  type BankNotification,
  type PromptContext,
} from '../domain/notifications';
import { AiError, chatJson } from '../lib/ai';
import { fromDate, toDate, type DateStr } from '../lib/dates';
import { HttpError, notFound } from '../lib/http';

export const notificationSchema = z.object({
  /** Pacote do app que gerou a notificação (ex.: com.nu.production). */
  app: z.string().min(1).max(200),
  appName: z.string().max(200).nullish(),
  title: z.string().max(500).nullish(),
  text: z.string().min(1).max(4000),
  postedAt: z.string().datetime({ offset: true }),
  /** Chave da notificação no Android: atualizações da mesma notificação não contam duas vezes. */
  key: z.string().max(500).nullish(),
});
export type NotificationInput = z.infer<typeof notificationSchema>;

export function notificationHash(n: NotificationInput): string {
  const parts = [n.app, n.key ?? n.postedAt, n.title ?? '', n.text];
  return createHash('sha256').update(parts.join('\u0001')).digest('hex');
}

async function promptContext(userId: string, today: DateStr): Promise<PromptContext> {
  const [accounts, cards, categories, recent] = await Promise.all([
    prisma.account.findMany({ where: { userId, archived: false }, orderBy: { name: 'asc' } }),
    prisma.creditCard.findMany({
      where: { userId, archived: false },
      include: { paymentAccount: { select: { name: true } } },
      orderBy: { name: 'asc' },
    }),
    prisma.category.findMany({ where: { userId }, orderBy: { name: 'asc' } }),
    prisma.transaction.findMany({
      where: { userId, isForecast: false, categoryId: { not: null }, type: { not: 'TRANSFER' }, counterpartOfId: null },
      orderBy: { date: 'desc' },
      take: 200,
      select: { description: true, externalName: true, categoryId: true },
    }),
  ]);
  // Um exemplo por descrição, os mais recentes primeiro (até 40).
  const seen = new Set<string>();
  const history: PromptContext['history'] = [];
  for (const t of recent) {
    const key = t.description.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    history.push({ description: t.description, merchant: t.externalName, categoryId: t.categoryId! });
    if (history.length >= 40) break;
  }
  const pick = (kind: 'EXPENSE' | 'INCOME') =>
    categories.filter((c) => c.kind === kind).map((c) => ({ id: c.id, name: c.name }));
  return {
    today,
    accounts: accounts.map((a) => ({ id: a.id, name: a.name })),
    cards: cards.map((c) => ({
      id: c.id,
      name: c.name,
      lastDigits: c.lastDigits,
      paymentAccountName: c.paymentAccount.name,
    })),
    categories: { EXPENSE: pick('EXPENSE'), INCOME: pick('INCOME') },
    history,
  };
}

/**
 * Recebe uma notificação de banco: a IA interpreta; se já existe o lançamento, dá baixa (pendente)
 * ou ignora (pago); senão vira sugestão. A mesma notificação enviada de novo não é processada outra vez.
 */
export async function ingestNotification(userId: string, input: NotificationInput, today: DateStr): Promise<Suggestion> {
  const hash = notificationHash(input);
  const existing = await prisma.suggestion.findUnique({ where: { userId_hash: { userId, hash } } });
  if (existing) return existing;
  let s: Suggestion;
  try {
    s = await prisma.suggestion.create({
      data: {
        userId,
        hash,
        status: 'ERROR',
        reason: 'Processando',
        app: input.app,
        appName: input.appName ?? null,
        title: input.title ?? null,
        text: input.text,
        postedAt: new Date(input.postedAt),
      },
    });
  } catch (e) {
    // Duas cópias chegando juntas: a outra já criou.
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
      return prisma.suggestion.findUniqueOrThrow({ where: { userId_hash: { userId, hash } } });
    }
    throw e;
  }
  return processSuggestion(s, today);
}

/** Interpreta (IA) e compara com os lançamentos. Também usado para tentar de novo após erro. */
export async function processSuggestion(s: Suggestion, today: DateStr): Promise<Suggestion> {
  const n: BankNotification = {
    app: s.app,
    appName: s.appName,
    title: s.title,
    text: s.text,
    postedAt: s.postedAt.toISOString(),
  };
  const ctx = await promptContext(s.userId, today);
  let parsed;
  try {
    const { system, user } = buildPrompt(n, ctx);
    parsed = parseAiResult(await chatJson(system, user), ctx, localDate(n.postedAt));
  } catch (e) {
    const reason = e instanceof AiError ? e.message : e instanceof z.ZodError ? 'Resposta da IA fora do formato' : String(e);
    return prisma.suggestion.update({ where: { id: s.id }, data: { status: 'ERROR', reason: reason.slice(0, 500) } });
  }

  const fields = {
    type: parsed.type,
    channel: parsed.channel,
    amount: parsed.amount,
    date: parsed.date ? toDate(parsed.date) : null,
    merchant: parsed.merchant,
    description: parsed.description,
    accountId: parsed.accountId,
    cardId: parsed.cardId,
    categoryId: parsed.categoryId,
    installments: parsed.installments,
    confidence: parsed.confidence,
  };
  if (!parsed.isTransaction) {
    return prisma.suggestion.update({
      where: { id: s.id },
      data: { ...fields, status: 'IGNORED', reason: parsed.reason ?? 'Não é uma movimentação' },
    });
  }

  return prisma.$transaction(async (tx) => {
    const [candidates, linkedRows] = await Promise.all([
      tx.transaction.findMany({
        where: { userId: s.userId, isForecast: false, amount: parsed.amount!, type: parsed.type! },
        select: { id: true, type: true, status: true, amount: true, date: true, accountId: true, cardId: true },
      }),
      tx.suggestion.findMany({
        where: { userId: s.userId, transactionId: { not: null }, id: { not: s.id } },
        select: { transactionId: true },
      }),
    ]);
    const linked = new Set(linkedRows.map((r) => r.transactionId!));
    const result = matchNotification(
      parsed,
      candidates.map((c) => ({ ...c, date: fromDate(c.date) })),
      linked,
    );
    if (result.action === 'pay') {
      await tx.transaction.update({
        where: { id: result.txId },
        data: { status: 'PAID', paidAt: toDate(parsed.date!) },
      });
      return tx.suggestion.update({
        where: { id: s.id },
        data: { ...fields, status: 'AUTO_PAID', reason: null, transactionId: result.txId },
      });
    }
    if (result.action === 'exists') {
      return tx.suggestion.update({
        where: { id: s.id },
        data: { ...fields, status: 'ALREADY_EXISTS', reason: null, transactionId: result.txId },
      });
    }
    return tx.suggestion.update({
      where: { id: s.id },
      data: { ...fields, status: 'PENDING', reason: result.reason ?? null },
    });
  });
}

export async function ownedSuggestion(userId: string, id: string): Promise<Suggestion> {
  const s = await prisma.suggestion.findFirst({ where: { id, userId } });
  if (!s) throw notFound('Sugestão');
  return s;
}

/** O usuário criou o lançamento a partir da sugestão. */
export async function acceptSuggestion(userId: string, id: string, transactionId: string | null) {
  const s = await ownedSuggestion(userId, id);
  if (transactionId) {
    const t = await prisma.transaction.findFirst({ where: { id: transactionId, userId } });
    if (!t) throw notFound('Lançamento');
  }
  return prisma.suggestion.update({ where: { id: s.id }, data: { status: 'ACCEPTED', transactionId, reason: null } });
}

export async function dismissSuggestion(userId: string, id: string) {
  const s = await ownedSuggestion(userId, id);
  return prisma.suggestion.update({ where: { id: s.id }, data: { status: 'DISMISSED' } });
}

/**
 * Desfaz o que foi automático: baixa dada por engano volta o lançamento para pendente; "já existia"
 * vira sugestão (era outro lançamento). Em ambos a notificação volta para a lista de sugestões.
 */
export async function undoSuggestion(userId: string, id: string) {
  const s = await ownedSuggestion(userId, id);
  if (s.status !== 'AUTO_PAID' && s.status !== 'ALREADY_EXISTS' && s.status !== 'IGNORED' && s.status !== 'DISMISSED') {
    throw new HttpError(400, 'Só dá para desfazer o que foi feito automaticamente, ignorado ou descartado');
  }
  return prisma.$transaction(async (tx) => {
    if (s.status === 'AUTO_PAID' && s.transactionId) {
      await tx.transaction.updateMany({
        where: { id: s.transactionId, userId, status: 'PAID' },
        data: { status: 'PENDING', paidAt: null },
      });
    }
    return tx.suggestion.update({
      where: { id: s.id },
      data: { status: 'PENDING', transactionId: null, reason: null },
    });
  });
}
