import { describe, expect, it } from 'vitest';
import { buildCashEvents, dailyBalances, type LedgerInvoice, type LedgerTx } from '../src/domain/cashflow';
import { categoryAmount, type CategoryOptions } from '../src/domain/categories';
import {
  forecastEffective,
  forecastRemaining,
  forecastTotalsByInvoice,
  mergeForecasts,
  shouldExpire,
  type ForecastLike,
} from '../src/domain/forecast';

const TODAY = '2026-11-18';

function tx(p: Partial<LedgerTx> & Pick<LedgerTx, 'type' | 'amount' | 'date'>): LedgerTx {
  return {
    id: Math.random().toString(36).slice(2),
    status: 'PAID',
    accountId: 'A',
    toAccountId: null,
    cardId: null,
    categoryId: null,
    ...p,
  };
}

function fc(p: Partial<ForecastLike> & Pick<ForecastLike, 'amount' | 'date'>): LedgerTx & ForecastLike {
  return {
    ...tx({ type: 'EXPENSE', status: 'PENDING', ...p }),
    isForecast: true,
    forecastState: 'OPEN',
    forecastAbated: 0,
    invoiceId: null,
    ...p,
  };
}

describe('restante e valor efetivo', () => {
  it('restante nunca fica negativo', () => {
    expect(forecastRemaining(10000, 7000)).toBe(3000);
    expect(forecastRemaining(10000, 10500)).toBe(0);
  });

  it('só previsões abertas e não vencidas contam', () => {
    expect(forecastEffective(fc({ amount: 10000, date: '2026-11-20', forecastAbated: 7000 }), TODAY)).toBe(3000);
    expect(forecastEffective(fc({ amount: 10000, date: TODAY }), TODAY)).toBe(10000);
    expect(forecastEffective(fc({ amount: 10000, date: '2026-11-17' }), TODAY)).toBe(0);
    expect(forecastEffective(fc({ amount: 10000, date: '2026-11-20', forecastState: 'CLOSED' }), TODAY)).toBe(0);
    expect(forecastEffective(fc({ amount: 10000, date: '2026-11-20', forecastState: 'EXPIRED' }), TODAY)).toBe(0);
  });

  it('expira previsão aberta com data passada', () => {
    expect(shouldExpire({ forecastState: 'OPEN', date: '2026-11-10' }, TODAY)).toBe(true);
    expect(shouldExpire({ forecastState: 'OPEN', date: TODAY }, TODAY)).toBe(false);
    expect(shouldExpire({ forecastState: 'CLOSED', date: '2026-11-10' }, TODAY)).toBe(false);
  });
});

describe('fluxo de caixa com previsões', () => {
  const real = [tx({ type: 'EXPENSE', amount: 3000, date: '2026-11-15', forecastId: 'F1' } as LedgerTx)];
  const forecasts = [
    fc({ id: 'F1', amount: 10000, date: '2026-11-20', forecastAbated: 3000 }),
    fc({ id: 'F2', amount: 5000, date: '2026-11-10' }), // vencida: não conta
    fc({ id: 'F3', amount: 2000, date: '2026-11-25', accountId: null, cardId: 'C', invoiceId: 'I' }),
  ];
  const invoices: LedgerInvoice[] = [{ id: 'I', paymentAccountId: 'A', dueDate: '2026-11-28', remaining: 1000 }];
  const days = ['2026-11-30'];

  it('desmarcado: só os lançamentos reais', () => {
    const b = dailyBalances(buildCashEvents(real, invoices, TODAY, null), 0, days);
    expect(b.get('2026-11-30')!.projected).toBe(-3000 - 1000);
  });

  it('marcado: soma o restante das previsões abertas, e as de cartão entram pela fatura', () => {
    const view = mergeForecasts(real, invoices, forecasts, TODAY);
    expect(view.invoices[0].remaining).toBe(3000);
    const b = dailyBalances(buildCashEvents(view.txs, view.invoices, TODAY, null), 0, days);
    // real 3000 + restante F1 7000 + fatura (1000 real + 2000 previsto)
    expect(b.get('2026-11-30')!.projected).toBe(-3000 - 7000 - 3000);
    expect(b.get('2026-11-30')!.realized).toBe(-3000);
  });

  it('total previsto por fatura', () => {
    expect(forecastTotalsByInvoice(forecasts, TODAY).get('I')).toBe(2000);
  });
});

describe('relatório por categoria com previsões', () => {
  const opts: CategoryOptions = { kind: 'EXPENSE', cardDate: 'purchase', basis: 'projected', today: TODAY };
  const base = { paysInvoiceId: null, invoiceDueDate: null, categoryId: 'gas' };

  it('abatimento não conta duas vezes', () => {
    const real = tx({ type: 'EXPENSE', amount: 3000, date: '2026-11-15' });
    const [, f] = mergeForecasts(
      [real],
      [],
      [fc({ amount: 10000, date: '2026-11-20', forecastAbated: 3000 })],
      TODAY,
    ).txs;
    const total =
      (categoryAmount({ ...real, ...base }, opts) ?? 0) + (categoryAmount({ ...f, ...base, isForecast: true }, opts) ?? 0);
    expect(total).toBe(10000);
  });

  it('previsão nunca entra no realizado (nem no cartão)', () => {
    const f = { ...fc({ amount: 2000, date: TODAY, accountId: null, cardId: 'C' }), ...base };
    expect(categoryAmount(f, { ...opts, basis: 'realized' })).toBeNull();
    expect(categoryAmount(f, opts)).toBe(2000);
  });
});
