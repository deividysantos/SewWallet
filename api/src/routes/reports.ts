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
import { initialBalanceOf, loadLedger } from '../services/ledger';
import { ensureRecurrences, horizon } from '../services/recurrence';

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
