import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db';
import { invoicePeriodForPurchase } from '../domain/invoice';
import { today } from '../lib/dates';
import { dateStr, id, parse } from '../lib/http';
import { loadLedger } from '../services/ledger';
import { importOfx, importSchema, previewOfxImport } from '../services/ofxImport';
import { ownedAccount, ownedCard } from '../services/owned';

export const cardsRouter = Router();

const day = z.number().int().min(1).max(31);
const cardSchema = z.object({
  name: z.string().trim().min(1).max(60),
  limit: z.number().int().min(0).nullish(),
  closingDay: day,
  dueDay: day,
  closingDayInNext: z.boolean().default(true),
  paymentAccountId: id,
  color: z.string().max(20).nullish(),
  archived: z.boolean().optional(),
  /** Últimos 4 dígitos, para reconhecer o cartão nas notificações. */
  lastDigits: z
    .string()
    .regex(/^\d{4}$/, 'Informe os 4 últimos dígitos')
    .nullish()
    .or(z.literal('').transform(() => null)),
});

/** Cartões com a fatura atual e o limite usado (tudo o que ainda não foi pago, incluindo parcelas futuras). */
cardsRouter.get('/', async (req, res) => {
  const t = today();
  const ledger = await loadLedger(req.userId, t);
  res.json(
    ledger.cards.map((card) => {
      const period = invoicePeriodForPurchase(t, card);
      const invoices = ledger.invoices.filter((i) => i.cardId === card.id);
      const current = invoices.find((i) => i.refMonth === period.refMonth);
      const used = invoices.reduce((s, i) => s + i.remaining, 0);
      return {
        ...card,
        currentInvoice: current ?? { id: null, ...period, total: 0, paid: 0, remaining: 0, status: 'OPEN' },
        limitUsed: used,
        limitAvailable: card.limit === null ? null : card.limit - used,
      };
    }),
  );
});

cardsRouter.get('/:id/invoices', async (req, res) => {
  await ownedCard(req.userId, req.params.id);
  const ledger = await loadLedger(req.userId, today());
  res.json(ledger.invoices.filter((i) => i.cardId === req.params.id));
});

const ofxPreviewSchema = z.object({ ofx: z.string().min(1).max(900_000) });

/** Prévia da importação de um OFX na fatura que fecha no mês `refMonth` (AAAA-MM-DD). */
cardsRouter.post('/:id/invoices/:refMonth/ofx/preview', async (req, res) => {
  const refMonth = parse(dateStr, req.params.refMonth);
  const body = parse(ofxPreviewSchema, req.body);
  res.json(await previewOfxImport(req.userId, req.params.id, refMonth, body.ofx));
});

cardsRouter.post('/:id/invoices/:refMonth/ofx/import', async (req, res) => {
  const refMonth = parse(dateStr, req.params.refMonth);
  const body = parse(importSchema, req.body);
  res.status(201).json(await importOfx(req.userId, req.params.id, refMonth, body));
});

cardsRouter.post('/', async (req, res) => {
  const body = parse(cardSchema, req.body);
  await ownedAccount(req.userId, body.paymentAccountId);
  res.status(201).json(await prisma.creditCard.create({ data: { ...body, userId: req.userId } }));
});

/** Mudar fechamento/vencimento vale para as próximas compras; faturas já criadas mantêm as datas. */
cardsRouter.put('/:id', async (req, res) => {
  await ownedCard(req.userId, req.params.id);
  const body = parse(cardSchema.partial(), req.body);
  if (body.paymentAccountId) await ownedAccount(req.userId, body.paymentAccountId);
  res.json(await prisma.creditCard.update({ where: { id: req.params.id }, data: body }));
});

/** Exclui o cartão com faturas e compras. */
cardsRouter.delete('/:id', async (req, res) => {
  await ownedCard(req.userId, req.params.id);
  await prisma.creditCard.delete({ where: { id: req.params.id } });
  res.status(204).end();
});
