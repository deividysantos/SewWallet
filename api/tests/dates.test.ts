import { describe, expect, it } from 'vitest';
import { addMonths, isDateStr, startOfWeek } from '../src/lib/dates';
import { occurrencesBetween } from '../src/services/recurrence';
import { splitInstallments } from '../src/services/transactions';
import { toDate } from '../src/lib/dates';

describe('datas', () => {
  it('addMonths limita ao fim do mês', () => {
    expect(addMonths('2027-01-31', 1)).toBe('2027-02-28');
    expect(addMonths('2026-11-15', 2)).toBe('2027-01-15');
    expect(addMonths('2026-03-10', -3)).toBe('2025-12-10');
  });
  it('valida formato', () => {
    expect(isDateStr('2026-02-30')).toBe(false);
    expect(isDateStr('2026-11-18')).toBe(true);
  });
  it('semana começa na segunda', () => {
    expect(startOfWeek('2026-11-18')).toBe('2026-11-16');
    expect(startOfWeek('2026-11-22')).toBe('2026-11-16');
  });
});

describe('fixos', () => {
  it('mensal no dia 31 não "escorrega" depois de fevereiro', () => {
    const rec = { startDate: toDate('2027-01-31'), frequency: 'MONTHLY' as const, interval: 1 };
    expect(occurrencesBetween(rec, '2027-01-30', '2027-04-30')).toEqual([
      '2027-01-31',
      '2027-02-28',
      '2027-03-31',
      '2027-04-30',
    ]);
  });
  it('gera só depois do que já foi gerado', () => {
    const rec = { startDate: toDate('2026-01-10'), frequency: 'MONTHLY' as const, interval: 1 };
    expect(occurrencesBetween(rec, '2026-03-10', '2026-05-31')).toEqual(['2026-04-10', '2026-05-10']);
  });
});

describe('parcelas', () => {
  it('diferença de centavos vai na primeira', () => {
    expect(splitInstallments(10000, 3)).toEqual([3334, 3333, 3333]);
  });
});
