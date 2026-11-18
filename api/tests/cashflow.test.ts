import { describe, expect, it } from 'vitest';
import {
  buildCashEvents,
  buildCashflowReport,
  dailyBalances,
  type LedgerInvoice,
  type LedgerTx,
} from '../src/domain/cashflow';

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

describe('saldo por dia', () => {
  const txs: LedgerTx[] = [
    tx({ type: 'INCOME', amount: 5000, date: '2026-11-05' }),
    tx({ type: 'EXPENSE', amount: 1000, date: '2026-11-10' }),
    // pendente atrasado: conta no previsto de HOJE
    tx({ type: 'EXPENSE', amount: 300, date: '2026-11-15', status: 'PENDING' }),
    // pendente futuro
    tx({ type: 'EXPENSE', amount: 700, date: '2026-11-25', status: 'PENDING' }),
    // compra no cartão não mexe na conta
    tx({ type: 'EXPENSE', amount: 9999, date: '2026-11-11', accountId: null, cardId: 'C' }),
  ];
  const invoices: LedgerInvoice[] = [{ id: 'I', paymentAccountId: 'A', dueDate: '2026-11-20', remaining: 2000 }];
  const events = buildCashEvents(txs, invoices, TODAY, null);
  const days = ['2026-11-10', '2026-11-15', '2026-11-18', '2026-11-20', '2026-11-25'];
  const b = dailyBalances(events, 10000, days);

  it('realizado só considera pagos', () => {
    expect(b.get('2026-11-10')).toEqual({ realized: 14000, projected: 14000 });
    expect(b.get('2026-11-25')!.realized).toBe(14000);
  });

  it('atrasado não reduz o previsto no dia original, e sim hoje', () => {
    expect(b.get('2026-11-15')!.projected).toBe(14000);
    expect(b.get('2026-11-18')!.projected).toBe(13700);
  });

  it('fatura entra no previsto no vencimento', () => {
    expect(b.get('2026-11-20')!.projected).toBe(11700);
    expect(b.get('2026-11-25')!.projected).toBe(11000);
  });
});

describe('transferências', () => {
  const t = [tx({ type: 'TRANSFER', amount: 500, date: '2026-11-02', accountId: 'A', toAccountId: 'B' })];

  it('entre contas filtradas é interna (não é entrada/saída)', () => {
    const r = buildCashflowReport({
      events: buildCashEvents(t, [], TODAY, null),
      initialBalance: 0,
      from: '2026-11-01',
      to: '2026-11-30',
      granularity: 'month',
      mode: 'period',
      basis: 'projected',
    });
    expect(r.totals).toEqual({ income: 0, expense: 0, transfersIn: 0, transfersOut: 0, net: 0 });
  });

  it('para conta fora do filtro conta como saída', () => {
    const events = buildCashEvents(t, [], TODAY, new Set(['A']));
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ kind: 'TRANSFER_OUT', delta: -500, internal: false });
  });
});

describe('relatório de fluxo de caixa', () => {
  const txs: LedgerTx[] = [
    tx({ type: 'INCOME', amount: 1000, date: '2026-09-10' }),
    tx({ type: 'EXPENSE', amount: 200, date: '2026-10-10' }),
    tx({ type: 'INCOME', amount: 500, date: '2026-11-10' }),
    tx({ type: 'EXPENSE', amount: 100, date: '2026-12-10', status: 'PENDING' }),
  ];
  const events = buildCashEvents(txs, [], TODAY, null);
  const base = { events, initialBalance: 50, granularity: 'month' as const, basis: 'projected' as const };

  it('com período começa do zero', () => {
    const r = buildCashflowReport({ ...base, from: '2026-10-01', to: '2026-11-30', mode: 'period' });
    expect(r.openingBalance).toBe(0);
    expect(r.buckets.map((x) => x.closing)).toEqual([-200, 300]);
  });

  it('acumulado traz saldo dos meses anteriores', () => {
    const r = buildCashflowReport({ ...base, from: '2026-10-01', to: '2026-12-31', mode: 'cumulative' });
    expect(r.openingBalance).toBe(1050);
    expect(r.buckets.map((x) => x.closing)).toEqual([850, 1350, 1250]);
  });

  it('realizado ignora pendentes', () => {
    const r = buildCashflowReport({ ...base, from: '2026-12-01', to: '2026-12-31', mode: 'cumulative', basis: 'realized' });
    expect(r.closingBalance).toBe(1350);
  });

  it('semanas começam na segunda e são cortadas pelo período', () => {
    const r = buildCashflowReport({ ...base, granularity: 'week', from: '2026-11-04', to: '2026-11-17', mode: 'period' });
    expect(r.buckets.map((x) => [x.start, x.end])).toEqual([
      ['2026-11-04', '2026-11-08'],
      ['2026-11-09', '2026-11-15'],
      ['2026-11-16', '2026-11-17'],
    ]);
    expect(r.buckets[1].income).toBe(500);
  });
});
