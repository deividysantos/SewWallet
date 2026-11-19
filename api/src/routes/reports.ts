import { Router } from 'express';
import { z } from 'zod';
import { buildCashEvents, buildCashflowReport, dailyBalances, type Granularity } from '../domain/cashflow';
import { counterpartPairIds, counterpartTotals } from '../domain/counterpart';
import { forecastEffective } from '../domain/forecast';
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
import { forecastsParam, refreshLedger } from '../services/forecasts';
import { initialBalanceOf, ledgerView, loadLedger, type Ledger, type TxView } from '../services/ledger';
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
  forecasts: forecastsParam,
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
  forecasts: forecastsParam,
});

function categoryWindow(q: { from?: DateStr; to?: DateStr }, t: DateStr): [DateStr, DateStr] {
  const from = q.from ?? startOfMonth(t);
  const to = q.to ?? endOfMonth(from);
  if (from > to) throw new HttpError(400, '"from" depois de "to"');
  return [from, to];
}

function categoryTxs(ledger: Ledger, txs: TxView[]): CategoryTx[] {
  const dueById = new Map(ledger.invoices.map((i) => [i.id, i.dueDate]));
  return txs.map((t) => ({
    isForecast: t.isForecast,
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
  await refreshLedger(req.userId, t, to);
  const ledger = await loadLedger(req.userId, t);
  const categories = await prisma.category.findMany({ where: { userId: req.userId } });
  const opts = { kind: q.kind, cardDate: q.cardDate, basis: q.basis, today: t };
  const txs = categoryTxs(ledger, ledgerView(ledger, q.forecasts).txs);

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
  await refreshLedger(req.userId, t, to);
  const ledger = await loadLedger(req.userId, t);
  const opts = { kind: q.kind, cardDate: q.cardDate, basis: q.basis, today: t };
  const categoryId = q.categoryId === 'none' ? null : q.categoryId;
  const viewTxs = ledgerView(ledger, q.forecasts).txs;
  const txs = categoryTxs(ledger, viewTxs);
  const dto = makeDto(ledger);
  // Previsões: o DTO usa o registro original (valor previsto/abatido/restante).
  const byId = new Map([...ledger.txs, ...ledger.forecasts].map((x) => [x.id, x]));

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

  await refreshLedger(req.userId, t, to);
  const ledger = await loadLedger(req.userId, t);
  const accFilter = q.accountIds ? new Set(q.accountIds) : null;
  const view = ledgerView(ledger, q.forecasts);

  res.json(
    buildCashflowReport({
      events: buildCashEvents(view.txs, view.invoices, t, accFilter),
      initialBalance: initialBalanceOf(ledger.accounts, accFilter),
      from,
      to,
      granularity: q.granularity,
      mode: q.mode,
      basis: q.basis,
    }),
  );
});

const forecastQuery = z.object({
  /** Qualquer dia do mês (AAAA-MM-DD); padrão: mês atual. */
  month: dateStr.optional(),
  accountIds: idList,
  cardIds: idList,
  type: z.enum(['INCOME', 'EXPENSE']).optional(),
  state: z.enum(['OPEN', 'CLOSED', 'EXPIRED', 'all']).default('all'),
});

/**
 * Previsões do mês, com previsto, abatido e restante, separadas em fixas e avulsas,
 * e os lançamentos reais que abateram cada uma.
 */
reportsRouter.get('/forecasts', async (req, res) => {
  const q = parse(forecastQuery, req.query);
  const t = today();
  const from = startOfMonth(q.month ?? t);
  const to = endOfMonth(from);
  await refreshLedger(req.userId, t, to);
  const ledger = await loadLedger(req.userId, t);
  const dto = makeDto(ledger);
  const accFilter = q.accountIds ? new Set(q.accountIds) : null;
  const cardFilter = q.cardIds ? new Set(q.cardIds) : null;

  const abatementsOf = new Map<string, TxView[]>();
  for (const tx of ledger.txs) {
    if (!tx.forecastId) continue;
    const list = abatementsOf.get(tx.forecastId) ?? [];
    list.push(tx);
    abatementsOf.set(tx.forecastId, list);
  }

  const items = ledger.forecasts
    .filter((f) => f.date >= from && f.date <= to)
    .filter((f) => q.state === 'all' || f.forecastState === q.state)
    .filter((f) => !q.type || f.type === q.type)
    .filter((f) => {
      if (!accFilter && !cardFilter) return true;
      return (!!f.accountId && !!accFilter?.has(f.accountId)) || (!!f.cardId && !!cardFilter?.has(f.cardId));
    })
    .map((f) => ({
      ...dto.tx(f),
      fixed: f.recurrenceId !== null,
      abatements: (abatementsOf.get(f.id) ?? []).map((a) => dto.tx(a)),
    }));

  const totals = (type: 'INCOME' | 'EXPENSE') => {
    const list = items.filter((i) => i.type === type);
    return {
      planned: list.reduce((s, i) => s + i.forecast!.planned, 0),
      abated: list.reduce((s, i) => s + i.forecast!.abated, 0),
      remaining: list.reduce((s, i) => s + i.forecast!.remaining, 0),
      /** Quanto ainda conta nos saldos (só abertas). */
      effective: list.reduce((s, i) => s + i.forecast!.effective, 0),
      count: list.length,
    };
  };

  res.json({ from, to, today: t, totals: { EXPENSE: totals('EXPENSE'), INCOME: totals('INCOME') }, items });
});

const dashboardQuery = z.object({
  /** Qualquer dia do mês (AAAA-MM-DD); padrão: mês atual. */
  month: dateStr.optional(),
  accountIds: idList,
  /** Considerar previsões abertas (pelo valor que falta abater). */
  forecasts: forecastsParam,
  /** false = tira os pares origem + contrapartida das receitas, despesas e categorias. */
  counterparts: forecastsParam,
});

/**
 * Painel do mês: saldos, receitas/despesas (cartão pela data da compra), maiores categorias,
 * faturas que vencem no mês, previsões e contrapartidas.
 */
reportsRouter.get('/dashboard', async (req, res) => {
  const q = parse(dashboardQuery, req.query);
  const t = today();
  const from = startOfMonth(q.month ?? t);
  const to = endOfMonth(from);
  await refreshLedger(req.userId, t, to);
  const ledger = await loadLedger(req.userId, t);
  const accFilter = q.accountIds ? new Set(q.accountIds) : null;
  const view = ledgerView(ledger, q.forecasts);
  const cardById = new Map(ledger.cards.map((c) => [c.id, c]));
  const inFilter = (id: string | null | undefined) => !!id && (!accFilter || accFilter.has(id));
  const touches = (x: TxView) =>
    !accFilter ||
    inFilter(x.accountId) ||
    inFilter(x.toAccountId) ||
    (!!x.cardId && inFilter(cardById.get(x.cardId)?.paymentAccountId));

  const pairs = q.counterparts ? new Set<string>() : counterpartPairIds(ledger.txs);
  const txs = categoryTxs(
    ledger,
    view.txs.filter((x) => touches(x) && !pairs.has(x.id)),
  );
  const categories = new Map(
    (await prisma.category.findMany({ where: { userId: req.userId } })).map((c) => [c.id, c]),
  );
  const report = (kind: 'INCOME' | 'EXPENSE', basis: 'projected' | 'realized') =>
    buildCategoryReport({ txs, categories, from, to, opts: { kind, cardDate: 'purchase', basis, today: t } });
  const expense = report('EXPENSE', 'projected');
  const income = report('INCOME', 'projected');
  const expenseRealized = report('EXPENSE', 'realized');
  const incomeRealized = report('INCOME', 'realized');

  const events = buildCashEvents(view.txs, view.invoices, t, accFilter);
  const before = addDays(from, -1);
  const days = [...new Set([before, t, to])].sort();
  const balances = dailyBalances(events, initialBalanceOf(ledger.accounts, accFilter), days);

  const invoices = ledger.invoices
    .filter((i) => i.dueDate >= from && i.dueDate <= to && inFilter(i.paymentAccountId))
    .filter((i) => i.total > 0 || i.paid > 0 || (q.forecasts && i.forecastTotal > 0))
    .map((i) => ({
      id: i.id,
      cardId: i.cardId,
      cardName: i.cardName,
      dueDate: i.dueDate,
      closingDate: i.closingDate,
      total: i.total,
      paid: i.paid,
      remaining: i.remaining,
      status: i.status,
      forecastTotal: q.forecasts ? i.forecastTotal : 0,
    }));
  const cards = ledger.cards
    .filter((c) => !c.archived && inFilter(c.paymentAccountId))
    .map((c) => ({
      id: c.id,
      name: c.name,
      color: c.color,
      limit: c.limit,
      limitUsed: ledger.invoices.filter((i) => i.cardId === c.id).reduce((s, i) => s + i.remaining, 0),
    }));

  const forecastsOfMonth = ledger.forecasts.filter((f) => f.date >= from && f.date <= to && touches(f));
  const forecastTotals = (type: 'INCOME' | 'EXPENSE') => {
    const list = forecastsOfMonth.filter((f) => f.type === type);
    return {
      planned: list.reduce((s, f) => s + f.forecastPlanned, 0),
      abated: list.reduce((s, f) => s + f.forecastAbated, 0),
      remaining: list.reduce((s, f) => s + f.forecastRemaining, 0),
      effective: list.reduce((s, f) => s + forecastEffective({ ...f, amount: f.forecastPlanned }, t), 0),
      count: list.length,
    };
  };

  const counterpartsOfMonth = ledger.txs.filter(
    (x) => x.counterpartOfId && x.date >= from && x.date <= to && inFilter(x.accountId),
  );

  const top = (r: ReturnType<typeof report>) => r.categories.filter((c) => c.total > 0).slice(0, 5);
  res.json({
    from,
    to,
    today: t,
    balance: {
      /** Saldo no fim do mês anterior (realizado se já passou). */
      opening: balances.get(before)!,
      /** Saldo de hoje (só faz sentido no mês atual). */
      today: balances.get(t)!,
      monthEnd: balances.get(to)!,
    },
    income: { projected: income.total, realized: incomeRealized.total },
    expense: { projected: expense.total, realized: expenseRealized.total },
    net: { projected: income.total - expense.total, realized: incomeRealized.total - expenseRealized.total },
    topExpenses: top(expense),
    topIncomes: top(income),
    invoices,
    cards,
    forecasts: { EXPENSE: forecastTotals('EXPENSE'), INCOME: forecastTotals('INCOME') },
    counterparts: {
      INCOME: counterpartTotals(counterpartsOfMonth.filter((x) => x.type === 'INCOME')),
      EXPENSE: counterpartTotals(counterpartsOfMonth.filter((x) => x.type === 'EXPENSE')),
    },
  });
});

const counterpartQuery = z.object({
  /** Qualquer dia do mês (AAAA-MM-DD); padrão: mês atual. O mês vale pela data da contrapartida. */
  month: dateStr.optional(),
  /** Conta da contrapartida. */
  accountIds: idList,
  /** Cartão do lançamento de origem. */
  cardIds: idList,
  /** INCOME = a receber de volta (origem é despesa); EXPENSE = a devolver (origem é receita). */
  type: z.enum(['INCOME', 'EXPENSE']).optional(),
  status: z.enum(['PENDING', 'PAID', 'all']).default('all'),
});

/** Contrapartidas do mês: cada uma com o lançamento de origem, e totais a receber × recebido. */
reportsRouter.get('/counterparts', async (req, res) => {
  const q = parse(counterpartQuery, req.query);
  const t = today();
  const from = startOfMonth(q.month ?? t);
  const to = endOfMonth(from);
  await refreshLedger(req.userId, t, to);
  const ledger = await loadLedger(req.userId, t);
  const dto = makeDto(ledger);
  const byId = new Map(ledger.txs.map((x) => [x.id, x]));
  const accFilter = q.accountIds ? new Set(q.accountIds) : null;
  const cardFilter = q.cardIds ? new Set(q.cardIds) : null;

  const pairs = ledger.txs
    .filter((x) => x.counterpartOfId && x.date >= from && x.date <= to)
    .map((cp) => ({ cp, origin: byId.get(cp.counterpartOfId!) }))
    .filter((p): p is { cp: TxView; origin: TxView } => !!p.origin)
    .filter(({ cp }) => !q.type || cp.type === q.type)
    .filter(({ cp, origin }) => {
      if (!accFilter && !cardFilter) return true;
      return (!!cp.accountId && !!accFilter?.has(cp.accountId)) || (!!origin.cardId && !!cardFilter?.has(origin.cardId));
    });
  const listed = pairs.filter(({ cp }) => q.status === 'all' || cp.status === q.status);
  listed.sort((a, b) => (a.cp.date < b.cp.date ? -1 : a.cp.date > b.cp.date ? 1 : 0));

  const totals = (type: 'INCOME' | 'EXPENSE') =>
    counterpartTotals(pairs.filter(({ cp }) => cp.type === type).map(({ cp }) => cp));

  res.json({
    from,
    to,
    today: t,
    totals: { INCOME: totals('INCOME'), EXPENSE: totals('EXPENSE') },
    items: listed.map(({ cp, origin }) => ({ ...dto.tx(cp), origin: dto.tx(origin) })),
  });
});