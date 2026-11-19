import type { Account, CreditCard } from '@prisma/client';
import { prisma } from '../db';
import type { LedgerInvoice, LedgerTx } from '../domain/cashflow';
import {
  forecastRemaining,
  forecastTotalsByInvoice,
  mergeForecasts,
  type ForecastState,
} from '../domain/forecast';
import { invoiceStatus, invoiceTotals, type InvoiceStatus } from '../domain/invoice';
import { fromDate, type DateStr } from '../lib/dates';

export interface TxView extends LedgerTx {
  description: string;
  paidAt: DateStr | null;
  notes: string | null;
  invoiceId: string | null;
  paysInvoiceId: string | null;
  installmentGroupId: string | null;
  installmentNumber: number | null;
  installmentTotal: number | null;
  recurrenceId: string | null;
  category: { id: string; name: string; kind: string; color: string | null; icon: string | null } | null;
  isForecast: boolean;
  forecastState: ForecastState | null;
  /** Previsão: valor previsto (em `amount` pode vir só o restante, na visão com previsões). */
  forecastPlanned: number;
  /** Previsão: quanto já foi abatido por lançamentos reais. */
  forecastAbated: number;
  /** Previsão: quanto falta abater. */
  forecastRemaining: number;
  /** Lançamento real: a previsão que ele abate. */
  forecastId: string | null;
  /** Contrapartida: o lançamento de origem que ela zera. */
  counterpartOfId: string | null;
  /** Origem: a contrapartida ligada a ele. */
  counterpartId: string | null;
}

export interface InvoiceView extends LedgerInvoice {
  cardId: string;
  cardName: string;
  refMonth: DateStr;
  closingDate: DateStr;
  total: number;
  paid: number;
  status: InvoiceStatus;
  /** Soma das previsões abertas nesta fatura (não entra no total nem no valor a pagar). */
  forecastTotal: number;
}

export interface Ledger {
  today: DateStr;
  accounts: Account[];
  cards: CreditCard[];
  /** Só lançamentos reais. */
  txs: TxView[];
  /** Todas as previsões (abertas, encerradas e expiradas), com abatido/restante. */
  forecasts: TxView[];
  invoices: InvoiceView[];
}

/**
 * Lançamentos e faturas para saldos/relatórios. Com `includeForecasts`, as previsões abertas
 * entram pelo valor restante (em conta, como pendentes; no cartão, somando à fatura).
 */
export function ledgerView(ledger: Ledger, includeForecasts: boolean): { txs: TxView[]; invoices: InvoiceView[] } {
  if (!includeForecasts) return { txs: ledger.txs, invoices: ledger.invoices };
  return mergeForecasts(ledger.txs, ledger.invoices, ledger.forecasts, ledger.today);
}

/**
 * Carrega todos os dados financeiros do usuário em memória.
 * Para uso pessoal (milhares de lançamentos) isso é rápido e simplifica os cálculos.
 */
export async function loadLedger(userId: string, today: DateStr): Promise<Ledger> {
  const [accounts, cards, rows, invoiceRows] = await Promise.all([
    prisma.account.findMany({ where: { userId }, orderBy: { name: 'asc' } }),
    prisma.creditCard.findMany({ where: { userId }, orderBy: { name: 'asc' } }),
    prisma.transaction.findMany({
      where: { userId },
      orderBy: [{ date: 'asc' }, { createdAt: 'asc' }],
      include: { category: { select: { id: true, name: true, kind: true, color: true, icon: true } } },
    }),
    prisma.invoice.findMany({ where: { card: { userId } }, orderBy: { refMonth: 'asc' } }),
  ]);

  const counterpartOf = new Map<string, string>();
  for (const t of rows) if (t.counterpartOfId) counterpartOf.set(t.counterpartOfId, t.id);

  const all: TxView[] = rows.map((t) => ({
    id: t.id,
    type: t.type,
    status: t.status,
    amount: t.amount,
    date: fromDate(t.date),
    paidAt: t.paidAt ? fromDate(t.paidAt) : null,
    description: t.description,
    notes: t.notes,
    accountId: t.accountId,
    toAccountId: t.toAccountId,
    cardId: t.cardId,
    categoryId: t.categoryId,
    category: t.category,
    invoiceId: t.invoiceId,
    paysInvoiceId: t.paysInvoiceId,
    installmentGroupId: t.installmentGroupId,
    installmentNumber: t.installmentNumber,
    installmentTotal: t.installmentTotal,
    recurrenceId: t.recurrenceId,
    isForecast: t.isForecast,
    forecastState: t.forecastState,
    forecastPlanned: t.isForecast ? t.amount : 0,
    forecastAbated: 0,
    forecastRemaining: 0,
    forecastId: t.forecastId,
    counterpartOfId: t.counterpartOfId,
    counterpartId: counterpartOf.get(t.id) ?? null,
  }));

  const txs = all.filter((t) => !t.isForecast);
  const forecasts = all.filter((t) => t.isForecast);
  const abatedBy = new Map<string, number>();
  for (const t of txs) {
    if (t.forecastId) abatedBy.set(t.forecastId, (abatedBy.get(t.forecastId) ?? 0) + t.amount);
  }
  for (const f of forecasts) {
    f.forecastAbated = abatedBy.get(f.id) ?? 0;
    f.forecastRemaining = forecastRemaining(f.amount, f.forecastAbated);
  }
  const forecastByInvoice = forecastTotalsByInvoice(forecasts, today);

  const itemsByInvoice = new Map<string, { type: string; amount: number }[]>();
  const paymentsByInvoice = new Map<string, { amount: number }[]>();
  for (const t of txs) {
    if (t.invoiceId) {
      const list = itemsByInvoice.get(t.invoiceId) ?? [];
      list.push(t);
      itemsByInvoice.set(t.invoiceId, list);
    }
    if (t.paysInvoiceId) {
      const list = paymentsByInvoice.get(t.paysInvoiceId) ?? [];
      list.push(t);
      paymentsByInvoice.set(t.paysInvoiceId, list);
    }
  }

  const cardById = new Map(cards.map((c) => [c.id, c]));
  const invoices: InvoiceView[] = invoiceRows.map((inv) => {
    const card = cardById.get(inv.cardId)!;
    const totals = invoiceTotals(itemsByInvoice.get(inv.id) ?? [], paymentsByInvoice.get(inv.id) ?? []);
    const period = { closingDate: fromDate(inv.closingDate), dueDate: fromDate(inv.dueDate) };
    return {
      id: inv.id,
      cardId: inv.cardId,
      cardName: card.name,
      paymentAccountId: card.paymentAccountId,
      refMonth: fromDate(inv.refMonth),
      ...period,
      ...totals,
      status: invoiceStatus(period, totals.total, totals.paid, today, card),
      forecastTotal: forecastByInvoice.get(inv.id) ?? 0,
    };
  });

  return { today, accounts, cards, txs, forecasts, invoices };
}

export function initialBalanceOf(accounts: Account[], filter: Set<string> | null): number {
  return accounts.filter((a) => !filter || filter.has(a.id)).reduce((s, a) => s + a.initialBalance, 0);
}
