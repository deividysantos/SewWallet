import { Router } from 'express';
import { z } from 'zod';
import { buildCashEvents, buildCashflowReport, type Granularity } from '../domain/cashflow';
import {
  addDays,
  addMonths,
  endOfMonth,
  endOfWeek,
  maxDate,
  startOfMonth,
  startOfWeek,
  today,
  type DateStr,
} from '../lib/dates';
import { dateStr, HttpError, idList, parse } from '../lib/http';
import { prisma } from '../db';
import {
  buildCategoryReport,
  categoryAmount,
  monthlyHistory,
  reportDate,
  type CategoryTx,
} from '../domain/categories';
import { initialBalanceOf, loadLedger, type Ledger } from '../services/ledger';
import { ensureRecurrences, horizon } from '../services/recurrence';
import { makeDto } from './transactions';

export const reportsRouter = Router();

const cashflowQuery = z.object({
  granularity: z.enum(['day', 'week', 'month']).default('month'),
  /** period: começa do zero, só o intervalo. cumulative: traz o saldo dos meses anteriores. */
  mode: z.enum(['period', 'cumulative']).default('cumulative'),
  /** projected: pagos + pendentes. realized: só pagos. */
  basis: z.enum(['projected', 'realized']).default('projected'),
  from: dateStr.optional(),
  to: dateStr.optional(),
  accountIds: idList,
});

function defaultWindow(t: DateStr, granularity: Granularity): [DateStr, DateStr] {
  switch (granularity) {
    case 'day':
      return [startOfMonth(t), endOfMonth(t)];
    case 'week':
      return [startOfWeek(addDays(t, -28)), endOfWeek(addDays(t, 56))];
    case 'month':
      return [startOfMonth(addMonths(t, -5)), endOfMonth(addMonths(t, 6))];
  }
}

const categoryQuery = z.object({
  kind: z.enum(['EXPENSE', 'INCOME']).default('EXPENSE'),
  cardDate: z.enum(['purchase', 'payment']).default('purchase'),
  basis: z.enum(['projected', 'realized']).default('projected'),
  from: dateStr.optional(),
  to: dateStr.optional(),
});

function categoryWindow(q: { from?: DateStr; to?: DateStr }, t: DateStr): [DateStr, DateStr] {
  const from = q.from ?? startOfMonth(t);
  const to = q.to ?? endOfMonth(from);
  if (from > to) throw new HttpError(400, '"from" depois de "to"');
  return [from, to];
}

function categoryTxs(ledger: Ledger): CategoryTx[] {
  const dueById = new Map(ledger.invoices.map((i) => [i.id, i.dueDate]));
  return ledger.txs.map((t) => ({
    id: t.id,
    type: t.type,
    status: t.status,
    amount: t.amount,
    date: t.date,
    cardId: t.cardId,
    categoryId: t.categoryId,
    paysInvoiceId: t.paysInvoiceId,
    invoiceDueDate: t.invoiceId ? (dueById.get(t.invoiceId) ?? null) : null,
  }));
}

/**
 * Quanto foi gasto (ou recebido) por categoria no intervalo, comparado ao período anterior
 * e à média dos 3 anteriores. Compras no cartão contam pela compra (ou pelo vencimento,
 * com cardDate=payment); estornos abatem; pagamentos de fatura e transferências não entram.
 */
reportsRouter.get('/categories', async (req, res) => {
  const q = parse(categoryQuery, req.query);
  const t = today();
  const [from, to] = categoryWindow(q, t);
  await ensureRecurrences(req.userId, maxDate(horizon(t), to));
  const ledger = await loadLedger(req.userId, t);
  const categories = await prisma.category.findMany({ where: { userId: req.userId } });
  const opts = { kind: q.kind, cardDate: q.cardDate, basis: q.basis, today: t };
  const txs = categoryTxs(ledger);

  res.json({
    ...buildCategoryReport({
      txs,
      categories: new Map(categories.map((c) => [c.id, c])),
      from,
      to,
      opts,
    }),
    history: monthlyHistory(txs, undefined, to, 6, opts),
  });
});

/** Uma categoria (`categoryId=none` = sem categoria): histórico de 6 meses e os lançamentos do intervalo. */
reportsRouter.get('/categories/detail', async (req, res) => {
  const q = parse(categoryQuery.extend({ categoryId: z.string().min(1) }), req.query);
  const t = today();
  const [from, to] = categoryWindow(q, t);
  await ensureRecurrences(req.userId, maxDate(horizon(t), to));
  const ledger = await loadLedger(req.userId, t);
  const opts = { kind: q.kind, cardDate: q.cardDate, basis: q.basis, today: t };
  const categoryId = q.categoryId === 'none' ? null : q.categoryId;
  const txs = categoryTxs(ledger);
  const dto = makeDto(ledger);
  const byId = new Map(ledger.txs.map((x) => [x.id, x]));

  const items = txs
    .filter((x) => x.categoryId === categoryId)
    .map((x) => ({ x, date: reportDate(x, opts.cardDate), amount: categoryAmount(x, opts) }))
    .filter((r) => r.amount !== null && r.date >= from && r.date <= to)
    .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0))
    .map((r) => ({ ...dto.tx(byId.get(r.x.id)!), reportDate: r.date, reportAmount: r.amount }));

  res.json({
    categoryId: q.categoryId,
    from,
    to,
    total: items.reduce((s, i) => s + (i.reportAmount ?? 0), 0),
    history: monthlyHistory(txs, categoryId, to, 6, opts),
    items,
  });
});

/** Fluxo de caixa por dia, semana ou mês. Cartões entram pela fatura, na data de vencimento. */
reportsRouter.get('/cashflow', async (req, res) => {
  const q = parse(cashflowQuery, req.query);
  const t = today();
  const [defFrom, defTo] = defaultWindow(t, q.granularity);
  const from = q.from ?? defFrom;
  const to = q.to ?? defTo;
  if (from > to) throw new HttpError(400, '"from" depois de "to"');

  await ensureRecurrences(req.userId, maxDate(horizon(t), to));
  const ledger = await loadLedger(req.userId, t);
  const accFilter = q.accountIds ? new Set(q.accountIds) : null;

  res.json(
    buildCashflowReport({
      events: buildCashEvents(ledger.txs, ledger.invoices, t, accFilter),
      initialBalance: initialBalanceOf(ledger.accounts, accFilter),
      from,
      to,
      granularity: q.granularity,
      mode: q.mode,
      basis: q.basis,
    }),
  );
});
