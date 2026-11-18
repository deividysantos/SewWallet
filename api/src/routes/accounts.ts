import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db';
import { buildCashEvents } from '../domain/cashflow';
import { endOfMonth, today } from '../lib/dates';
import { parse } from '../lib/http';
import { loadLedger } from '../services/ledger';
import { ownedAccount } from '../services/owned';

export const accountsRouter = Router();

const accountSchema = z.object({
  name: z.string().trim().min(1).max(60),
  type: z.enum(['CHECKING', 'SAVINGS', 'WALLET', 'INVESTMENT', 'OTHER']).default('CHECKING'),
  /** Centavos; pode ser negativo (conta no cheque especial). */
  initialBalance: z.number().int().default(0),
  color: z.string().max(20).nullish(),
  archived: z.boolean().optional(),
});

/** Contas com saldo atual (realizado) e previsto para o fim do mês. */
accountsRouter.get('/', async (req, res) => {
  const t = today();
  const ledger = await loadLedger(req.userId, t);
  const events = buildCashEvents(ledger.txs, ledger.invoices, t, null);
  const monthEnd = endOfMonth(t);

  res.json(
    ledger.accounts.map((a) => {
      let balance = a.initialBalance;
      let projectedMonthEnd = a.initialBalance;
      for (const e of events) {
        if (e.accountId !== a.id) continue;
        if (e.paid && e.date <= t) balance += e.delta;
        if (e.date <= monthEnd) projectedMonthEnd += e.delta;
      }
      return { ...a, balance, projectedMonthEnd };
    }),
  );
});

accountsRouter.post('/', async (req, res) => {
  const body = parse(accountSchema, req.body);
  res.status(201).json(await prisma.account.create({ data: { ...body, userId: req.userId } }));
});

accountsRouter.put('/:id', async (req, res) => {
  await ownedAccount(req.userId, req.params.id);
  const body = parse(accountSchema.partial(), req.body);
  res.json(await prisma.account.update({ where: { id: req.params.id }, data: body }));
});

/** Exclui a conta e os lançamentos dela. Falha (409) se algum cartão paga a fatura por ela. */
accountsRouter.delete('/:id', async (req, res) => {
  await ownedAccount(req.userId, req.params.id);
  await prisma.account.delete({ where: { id: req.params.id } });
  res.status(204).end();
});
