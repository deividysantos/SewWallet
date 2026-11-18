import { Router } from 'express';
import { z } from 'zod';
import { buildCashEvents, dailyBalances } from '../domain/cashflow';
import { addDays, endOfMonth, maxDate, startOfMonth, today, type DateStr } from '../lib/dates';
import { dateStr, HttpError, idList, parse } from '../lib/http';
import { initialBalanceOf, loadLedger, type InvoiceView, type Ledger, type TxView } from '../services/ledger';
import { ownedTransaction } from '../services/owned';
import { ensureRecurrences, horizon } from '../services/recurrence';
import {
  createTransaction,
  createTxSchema,
  deleteTransaction,
  scopeSchema,
  setTransactionStatus,
  updateTransaction,
  updateTxSchema,
} from '../services/transactions';

export const transactionsRouter = Router();

const listQuery = z.object({
  from: dateStr.optional(),
  to: dateStr.optional(),
  accountIds: idList,
  cardIds: idList,
  categoryIds: idList,
  type: z.enum(['INCOME', 'EXPENSE', 'TRANSFER']).optional(),
  status: z.enum(['PENDING', 'PAID']).optional(),
  search: z.string().max(100).optional(),
  includeCards: z
    .enum(['true', 'false'])
    .default('true')
    .transform((v) => v === 'true'),
});

const normalize = (s: string) =>
  s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase();

function makeDto(ledger: Ledger) {
  const accountById = new Map(ledger.accounts.map((a) => [a.id, a]));
  const cardById = new Map(ledger.cards.map((c) => [c.id, c]));
  const invoiceById = new Map(ledger.invoices.map((i) => [i.id, i]));
  const ref = (m: Map<string, { id: string; name: string }>, id: string | null) => {
    const row = id ? m.get(id) : undefined;
    return row ? { id: row.id, name: row.name } : null;
  };

  return {
    cardById,
    tx: (t: TxView) => {
      const inv = t.invoiceId ? invoiceById.get(t.invoiceId) : undefined;
      return {
        kind: 'transaction' as const,
        id: t.id,
        type: t.type,
        status: t.status,
        description: t.description,
        amount: t.amount,
        date: t.date,
        paidAt: t.paidAt,
        notes: t.notes,
        overdue: !t.cardId && t.status === 'PENDING' && t.date < ledger.today,
        affectsBalance: !t.cardId,
        category: t.category,
        account: ref(accountById, t.accountId),
        toAccount: ref(accountById, t.toAccountId),
        card: ref(cardById, t.cardId),
        invoice: inv ? { id: inv.id, refMonth: inv.refMonth, dueDate: inv.dueDate } : null,
        paysInvoiceId: t.paysInvoiceId,
        installment: t.installmentGroupId
          ? { groupId: t.installmentGroupId, number: t.installmentNumber, total: t.installmentTotal }
          : null,
        recurrenceId: t.recurrenceId,
      };
    },
    invoice: (i: InvoiceView) => ({
      kind: 'invoice' as const,
      id: i.id,
      description: `Fatura ${i.cardName}`,
      date: i.dueDate,
      card: ref(cardById, i.cardId),
      account: ref(accountById, i.paymentAccountId),
      refMonth: i.refMonth,
      closingDate: i.closingDate,
      dueDate: i.dueDate,
      total: i.total,
      paid: i.paid,
      remaining: i.remaining,
      status: i.status,
      overdue: i.status === 'OVERDUE',
    }),
  };
}

/**
 * Lançamentos agrupados por dia, com o saldo das contas no FINAL de cada dia:
 * `realized` (só pagos) e `projected` (pagos + pendentes). Filtros de categoria/tipo/status/busca
 * mudam só a lista; os saldos sempre consideram tudo das contas filtradas.
 */
transactionsRouter.get('/', async (req, res) => {
  const q = parse(listQuery, req.query);
  const t = today();
  const from = q.from ?? startOfMonth(t);
  const to = q.to ?? endOfMonth(t);
  if (from > to) throw new HttpError(400, '"from" depois de "to"');

  await ensureRecurrences(req.userId, maxDate(horizon(t), to));
  const ledger = await loadLedger(req.userId, t);
  const accFilter = q.accountIds ? new Set(q.accountIds) : null;
  const cardFilter = q.cardIds ? new Set(q.cardIds) : null;
  const catFilter = q.categoryIds ? new Set(q.categoryIds) : null;
  const search = q.search ? normalize(q.search) : null;
  const dto = makeDto(ledger);

  const touchesAccounts = (ids: (string | null | undefined)[]) =>
    !accFilter || ids.some((id) => id && accFilter.has(id));

  const byDay = new Map<DateStr, unknown[]>();
  const push = (date: DateStr, item: unknown) => {
    const list = byDay.get(date) ?? [];
    list.push(item);
    byDay.set(date, list);
  };
  const summary = { income: 0, expense: 0, cardExpense: 0 };

  for (const tx of ledger.txs) {
    if (tx.date < from || tx.date > to) continue;
    if (tx.cardId && (!q.includeCards || (cardFilter && !cardFilter.has(tx.cardId)))) continue;
    if (!tx.cardId && cardFilter) continue;
    const payAcc = tx.cardId ? dto.cardById.get(tx.cardId)?.paymentAccountId : null;
    if (!touchesAccounts([tx.accountId, tx.toAccountId, payAcc])) continue;
    if (catFilter && !(tx.categoryId && catFilter.has(tx.categoryId))) continue;
    if (q.type && tx.type !== q.type) continue;
    if (q.status && tx.status !== q.status) continue;
    if (search && !normalize(tx.description).includes(search)) continue;

    push(tx.date, dto.tx(tx));
    if (tx.cardId) {
      if (tx.type === 'EXPENSE') summary.cardExpense += tx.amount;
      else if (tx.type === 'INCOME') summary.cardExpense -= tx.amount;
    } else if (tx.type === 'INCOME') summary.income += tx.amount;
    else if (tx.type === 'EXPENSE') summary.expense += tx.amount;
  }

  // A fatura aparece só enquanto tem valor a pagar; depois de paga, quem aparece é o lançamento de pagamento.
  const showInvoices = !catFilter && !search && (!q.type || q.type === 'EXPENSE') && q.status !== 'PAID';
  if (showInvoices) {
    for (const inv of ledger.invoices) {
      if (inv.dueDate < from || inv.dueDate > to || inv.remaining <= 0) continue;
      if (cardFilter && !cardFilter.has(inv.cardId)) continue;
      if (!touchesAccounts([inv.paymentAccountId])) continue;
      push(inv.dueDate, dto.invoice(inv));
    }
  }

  if (t >= from && t <= to && !byDay.has(t)) byDay.set(t, []);
  const days = [...byDay.keys()].sort();
  const openingDay = addDays(from, -1);
  const events = buildCashEvents(ledger.txs, ledger.invoices, t, accFilter);
  const balances = dailyBalances(events, initialBalanceOf(ledger.accounts, accFilter), [openingDay, ...days]);

  res.json({
    from,
    to,
    today: t,
    openingBalance: balances.get(openingDay),
    closingBalance: balances.get(days.at(-1) ?? openingDay),
    summary,
    days: days.map((date) => ({ date, balance: balances.get(date), items: byDay.get(date) })),
  });
});

transactionsRouter.get('/:id', async (req, res) => {
  await ownedTransaction(req.userId, req.params.id);
  const t = today();
  const ledger = await loadLedger(req.userId, t);
  const tx = ledger.txs.find((x) => x.id === req.params.id)!;
  res.json(makeDto(ledger).tx(tx));
});

transactionsRouter.post('/', async (req, res) => {
  const body = parse(createTxSchema, req.body);
  const created = await createTransaction(req.userId, body, today());
  res.status(201).json({ count: created.length, transactions: created });
});

/** ?scope=one|future|all (future/all só para fixos e parcelados). */
transactionsRouter.put('/:id', async (req, res) => {
  const scope = parse(scopeSchema, req.query.scope);
  const body = parse(updateTxSchema, req.body);
  res.json(await updateTransaction(req.userId, req.params.id, body, scope, today()));
});

transactionsRouter.patch('/:id/status', async (req, res) => {
  const { status } = parse(z.object({ status: z.enum(['PENDING', 'PAID']) }), req.body);
  res.json(await setTransactionStatus(req.userId, req.params.id, status, today()));
});

transactionsRouter.delete('/:id', async (req, res) => {
  const scope = parse(scopeSchema, req.query.scope);
  const deleted = await deleteTransaction(req.userId, req.params.id, scope);
  res.json({ deleted });
});
