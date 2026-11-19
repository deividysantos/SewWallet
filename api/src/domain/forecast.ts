import type { DateStr } from '../lib/dates';
import type { LedgerInvoice, LedgerTx } from './cashflow';

export type ForecastState = 'OPEN' | 'CLOSED' | 'EXPIRED';

/** Dados mínimos de uma previsão. `amount` é o valor previsto. */
export interface ForecastLike extends LedgerTx {
  forecastState: ForecastState | null;
  invoiceId: string | null;
  /** Soma dos lançamentos reais que abatem esta previsão. */
  forecastAbated: number;
}

/** Quanto ainda falta abater (nunca negativo). */
export function forecastRemaining(planned: number, abated: number): number {
  return Math.max(0, planned - abated);
}

/**
 * Quanto a previsão conta em saldos e relatórios: o restante, só enquanto está aberta
 * e a data não passou. Encerradas e expiradas não contam.
 */
export function forecastEffective(f: ForecastLike, today: DateStr): number {
  if (f.forecastState !== 'OPEN' || f.date < today) return 0;
  return forecastRemaining(f.amount, f.forecastAbated);
}

/** Previsões abertas que já passaram da data e devem virar EXPIRED. */
export function shouldExpire(f: { forecastState: ForecastState | null; date: DateStr }, today: DateStr): boolean {
  return f.forecastState === 'OPEN' && f.date < today;
}

/**
 * Junta as previsões que ainda contam aos lançamentos reais:
 * - previsões em conta entram como lançamentos pendentes, pelo valor restante;
 * - previsões no cartão somam ao valor a pagar da fatura delas (só para saldos/projeções).
 */
export function mergeForecasts<T extends LedgerTx, F extends T & ForecastLike, I extends LedgerInvoice>(
  txs: T[],
  invoices: I[],
  forecasts: F[],
  today: DateStr,
): { txs: T[]; invoices: I[] } {
  const extra: T[] = [];
  const byInvoice = new Map<string, number>();
  for (const f of forecasts) {
    const amount = forecastEffective(f, today);
    if (amount <= 0) continue;
    extra.push({ ...f, amount, status: 'PENDING' });
    if (f.cardId && f.invoiceId) {
      const sign = f.type === 'INCOME' ? -1 : 1;
      byInvoice.set(f.invoiceId, (byInvoice.get(f.invoiceId) ?? 0) + sign * amount);
    }
  }
  const merged = [...txs, ...extra].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  return {
    txs: merged,
    invoices: invoices.map((inv) => {
      const add = byInvoice.get(inv.id);
      return add ? { ...inv, remaining: Math.max(0, inv.remaining + add) } : inv;
    }),
  };
}

/** Soma das previsões de cartão que ainda contam, por fatura. */
export function forecastTotalsByInvoice(forecasts: ForecastLike[], today: DateStr): Map<string, number> {
  const out = new Map<string, number>();
  for (const f of forecasts) {
    if (!f.cardId || !f.invoiceId) continue;
    const amount = forecastEffective(f, today);
    if (amount <= 0) continue;
    out.set(f.invoiceId, (out.get(f.invoiceId) ?? 0) + (f.type === 'INCOME' ? -amount : amount));
  }
  return out;
}
