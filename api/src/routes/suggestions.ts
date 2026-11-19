import type { Prisma, Suggestion } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db';
import { aiConfigured } from '../lib/ai';
import { addDays, fromDate, today, toDate } from '../lib/dates';
import { id, parse } from '../lib/http';
import {
  acceptSuggestion,
  dismissSuggestion,
  ingestNotification,
  notificationSchema,
  ownedSuggestion,
  processSuggestion,
  undoSuggestion,
} from '../services/suggestions';

/** Sugestões de lançamento a partir das notificações dos bancos (lidas no celular). */
export const suggestionsRouter = Router();

async function toDto(rows: Suggestion[]) {
  const txIds = rows.map((r) => r.transactionId).filter((x): x is string => !!x);
  const txs = txIds.length
    ? await prisma.transaction.findMany({
        where: { id: { in: txIds } },
        select: { id: true, description: true, date: true, amount: true, status: true },
      })
    : [];
  const byId = new Map(txs.map((t) => [t.id, t]));
  return rows.map((s) => {
    const t = s.transactionId ? byId.get(s.transactionId) : undefined;
    return {
      id: s.id,
      status: s.status,
      reason: s.reason,
      app: s.app,
      appName: s.appName,
      title: s.title,
      text: s.text,
      postedAt: s.postedAt.toISOString(),
      type: s.type,
      channel: s.channel,
      amount: s.amount,
      date: s.date ? fromDate(s.date) : null,
      merchant: s.merchant,
      description: s.description,
      accountId: s.accountId,
      cardId: s.cardId,
      categoryId: s.categoryId,
      installments: s.installments,
      confidence: s.confidence,
      transaction: t ? { id: t.id, description: t.description, date: fromDate(t.date), amount: t.amount, status: t.status } : null,
    };
  });
}

/** O celular envia cada notificação de banco aqui. */
suggestionsRouter.post('/notifications', async (req, res) => {
  const body = parse(notificationSchema, req.body);
  const s = await ingestNotification(req.userId, body, today());
  res.status(201).json((await toDto([s]))[0]);
});

/**
 * pending: sugestões esperando decisão (e as que deram erro na IA).
 * processed: o que foi feito sozinho, aceito, descartado ou ignorado nos últimos 30 dias.
 */
suggestionsRouter.get('/', async (req, res) => {
  const { view } = parse(z.object({ view: z.enum(['pending', 'processed']).default('pending') }), req.query);
  const where: Prisma.SuggestionWhereInput =
    view === 'pending'
      ? { userId: req.userId, status: { in: ['PENDING', 'ERROR'] } }
      : {
          userId: req.userId,
          status: { in: ['AUTO_PAID', 'ALREADY_EXISTS', 'IGNORED', 'ACCEPTED', 'DISMISSED'] },
          updatedAt: { gte: toDate(addDays(today(), -30)) },
        };
  const rows = await prisma.suggestion.findMany({ where, orderBy: { postedAt: 'desc' }, take: 200 });
  res.json({ aiConfigured: aiConfigured(), items: await toDto(rows) });
});

suggestionsRouter.get('/count', async (req, res) => {
  const pending = await prisma.suggestion.count({ where: { userId: req.userId, status: { in: ['PENDING', 'ERROR'] } } });
  res.json({ pending });
});

suggestionsRouter.post('/:id/accept', async (req, res) => {
  const { transactionId } = parse(z.object({ transactionId: id.nullish() }), req.body ?? {});
  res.json((await toDto([await acceptSuggestion(req.userId, req.params.id, transactionId ?? null)]))[0]);
});

suggestionsRouter.post('/:id/dismiss', async (req, res) => {
  res.json((await toDto([await dismissSuggestion(req.userId, req.params.id)]))[0]);
});

suggestionsRouter.post('/:id/undo', async (req, res) => {
  res.json((await toDto([await undoSuggestion(req.userId, req.params.id)]))[0]);
});

/** Tenta interpretar de novo (depois de um erro da IA, por exemplo). */
suggestionsRouter.post('/:id/retry', async (req, res) => {
  const s = await ownedSuggestion(req.userId, req.params.id);
  res.json((await toDto([await processSuggestion(s, today())]))[0]);
});
