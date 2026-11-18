import { describe, expect, it } from 'vitest';
import {
  buildCategoryReport,
  categoryAmount,
  monthlyHistory,
  shiftWindow,
  type CategoryOptions,
  type CategoryTx,
} from '../src/domain/categories';

const TODAY = '2026-11-18';
const OPTS: CategoryOptions = { kind: 'EXPENSE', cardDate: 'purchase', basis: 'projected', today: TODAY };

let seq = 0;
function tx(p: Partial<CategoryTx> & Pick<CategoryTx, 'type' | 'amount' | 'date'>): CategoryTx {
  return {
    id: `t${++seq}`,
    status: 'PAID',
    cardId: null,
    categoryId: 'food',
    paysInvoiceId: null,
    invoiceDueDate: null,
    ...p,
  };
}

const CATS = new Map([
  ['food', { name: 'Alimentação', color: '#E53935', icon: 'restaurant' }],
  ['home', { name: 'Casa', color: null, icon: 'home' }],
]);

describe('o que entra no relatório', () => {
  it('pagamento de fatura e transferência nunca contam (as compras já contaram)', () => {
    expect(categoryAmount(tx({ type: 'EXPENSE', amount: 900, date: '2026-11-10', paysInvoiceId: 'i1', categoryId: null }), OPTS)).toBeNull();
    expect(categoryAmount(tx({ type: 'TRANSFER', amount: 100, date: '2026-11-10' }), OPTS)).toBeNull();
  });

  it('estorno no cartão abate a despesa; receita na conta não entra em despesas', () => {
    expect(categoryAmount(tx({ type: 'INCOME', amount: 50, date: '2026-11-10', cardId: 'c1' }), OPTS)).toBe(-50);
    expect(categoryAmount(tx({ type: 'INCOME', amount: 5000, date: '2026-11-10' }), OPTS)).toBeNull();
  });

  it('em receitas, estorno de cartão não conta como receita', () => {
    const income = { ...OPTS, kind: 'INCOME' as const };
    expect(categoryAmount(tx({ type: 'INCOME', amount: 5000, date: '2026-11-10' }), income)).toBe(5000);
    expect(categoryAmount(tx({ type: 'INCOME', amount: 50, date: '2026-11-10', cardId: 'c1' }), income)).toBeNull();
  });

  it('realizado: só pagos na conta; no cartão, compras até hoje', () => {
    const realized = { ...OPTS, basis: 'realized' as const };
    expect(categoryAmount(tx({ type: 'EXPENSE', amount: 10, date: '2026-11-25', status: 'PENDING' }), realized)).toBeNull();
    expect(categoryAmount(tx({ type: 'EXPENSE', amount: 10, date: '2026-11-10', cardId: 'c1', status: 'PENDING' }), realized)).toBe(10);
    expect(categoryAmount(tx({ type: 'EXPENSE', amount: 10, date: '2026-12-10', cardId: 'c1' }), realized)).toBeNull();
  });
});

describe('períodos', () => {
  it('meses inteiros andam por mês, inclusive por fevereiro', () => {
    expect(shiftWindow('2026-03-01', '2026-03-31', -1)).toEqual(['2026-02-01', '2026-02-28']);
    expect(shiftWindow('2026-01-01', '2026-12-31', -1)).toEqual(['2025-01-01', '2025-12-31']);
    expect(shiftWindow('2028-03-01', '2028-03-31', -1)).toEqual(['2028-02-01', '2028-02-29']);
  });

  it('intervalo solto anda pelo número de dias', () => {
    expect(shiftWindow('2026-11-10', '2026-11-16', -1)).toEqual(['2026-11-03', '2026-11-09']);
  });
});

describe('relatório', () => {
  const txs = [
    tx({ type: 'EXPENSE', amount: 3000, date: '2026-11-05' }),
    tx({ type: 'EXPENSE', amount: 1000, date: '2026-11-08', categoryId: 'home' }),
    tx({ type: 'EXPENSE', amount: 2000, date: '2026-11-20', cardId: 'c1', invoiceDueDate: '2026-12-12' }),
    tx({ type: 'INCOME', amount: 500, date: '2026-11-21', cardId: 'c1', invoiceDueDate: '2026-12-12' }), // estorno
    tx({ type: 'EXPENSE', amount: 400, date: '2026-11-09', categoryId: null }),
    tx({ type: 'EXPENSE', amount: 7000, date: '2026-11-12', paysInvoiceId: 'i0', categoryId: null }), // fatura
    tx({ type: 'EXPENSE', amount: 2400, date: '2026-10-05' }),
    tx({ type: 'EXPENSE', amount: 1200, date: '2026-09-05' }),
    tx({ type: 'EXPENSE', amount: 600, date: '2026-08-05' }),
  ];

  it('soma por categoria, fatia, anterior e média', () => {
    const r = buildCategoryReport({ txs, categories: CATS, from: '2026-11-01', to: '2026-11-30', opts: OPTS });
    expect(r.total).toBe(3000 + 1000 + 2000 - 500 + 400);
    expect(r.previousFrom).toBe('2026-10-01');
    expect(r.previousTotal).toBe(2400);
    expect(r.averageTotal).toBe(Math.round((2400 + 1200 + 600) / 3));

    const food = r.categories[0];
    expect(food).toMatchObject({ id: 'food', name: 'Alimentação', total: 4500, count: 3, previous: 2400, average: 1400 });
    expect(food.share).toBeCloseTo(4500 / r.total);

    const none = r.categories.find((c) => c.id === null)!;
    expect(none).toMatchObject({ name: 'Sem categoria', total: 400 }, );
    expect(r.categories.map((c) => c.id)).toEqual(['food', 'home', null]);
  });

  it('na visão por pagamento, a compra no cartão vai para o mês do vencimento', () => {
    const byPayment = { ...OPTS, cardDate: 'payment' as const };
    const nov = buildCategoryReport({ txs, categories: CATS, from: '2026-11-01', to: '2026-11-30', opts: byPayment });
    const dec = buildCategoryReport({ txs, categories: CATS, from: '2026-12-01', to: '2026-12-31', opts: byPayment });
    expect(nov.total).toBe(3000 + 1000 + 400);
    expect(dec.total).toBe(2000 - 500);
  });

  it('histórico mensal termina no mês pedido', () => {
    const h = monthlyHistory(txs, 'food', '2026-11-30', 4, OPTS);
    expect(h).toEqual([
      { month: '2026-08-01', total: 600 },
      { month: '2026-09-01', total: 1200 },
      { month: '2026-10-01', total: 2400 },
      { month: '2026-11-01', total: 4500 },
    ]);
  });
});
