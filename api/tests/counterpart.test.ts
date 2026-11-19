import { describe, expect, it } from 'vitest';
import { counterpartPairIds, counterpartTotals } from '../src/domain/counterpart';

describe('contrapartidas', () => {
  it('marca os dois lados de cada par', () => {
    const ids = counterpartPairIds([
      { id: 'o1', counterpartOfId: null },
      { id: 'c1', counterpartOfId: 'o1' },
      { id: 'x', counterpartOfId: null },
      { id: 'orphan', counterpartOfId: 'missing' },
    ]);
    expect([...ids].sort()).toEqual(['c1', 'o1']);
  });

  it('separa pendente e já recebido', () => {
    expect(
      counterpartTotals([
        { amount: 100, status: 'PENDING' },
        { amount: 50, status: 'PAID' },
        { amount: 30, status: 'PENDING' },
      ]),
    ).toEqual({ pending: 130, settled: 50, count: 3 });
  });
});
