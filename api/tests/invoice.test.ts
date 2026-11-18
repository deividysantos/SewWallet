import { describe, expect, it } from 'vitest';
import { invoicePeriodForPurchase, invoiceStatus, invoiceTotals } from '../src/domain/invoice';

const nubank = { closingDay: 5, dueDay: 12, closingDayInNext: true };
const itau = { closingDay: 25, dueDay: 5, closingDayInNext: true };

describe('fatura de uma compra', () => {
  it('compra antes do fechamento entra na fatura do mês', () => {
    expect(invoicePeriodForPurchase('2026-11-04', nubank)).toEqual({
      refMonth: '2026-11-01',
      closingDate: '2026-11-05',
      dueDate: '2026-11-12',
    });
  });

  it('compra no dia do fechamento vai para a próxima (padrão)', () => {
    expect(invoicePeriodForPurchase('2026-11-05', nubank).refMonth).toBe('2026-12-01');
  });

  it('compra no dia do fechamento fica na atual quando configurado', () => {
    expect(invoicePeriodForPurchase('2026-11-05', { ...nubank, closingDayInNext: false }).refMonth).toBe(
      '2026-11-01',
    );
  });

  it('vencimento antes do dia de fechamento cai no mês seguinte', () => {
    expect(invoicePeriodForPurchase('2026-11-20', itau)).toEqual({
      refMonth: '2026-11-01',
      closingDate: '2026-11-25',
      dueDate: '2026-12-05',
    });
  });

  it('virada de ano', () => {
    expect(invoicePeriodForPurchase('2026-12-28', itau)).toEqual({
      refMonth: '2027-01-01',
      closingDate: '2027-01-25',
      dueDate: '2027-02-05',
    });
  });

  it('fechamento dia 31 em fevereiro usa o último dia do mês', () => {
    const card = { closingDay: 31, dueDay: 10, closingDayInNext: true };
    expect(invoicePeriodForPurchase('2027-02-27', card).closingDate).toBe('2027-02-28');
    expect(invoicePeriodForPurchase('2027-02-28', card).refMonth).toBe('2027-03-01');
  });

  it('parcelas vão para as faturas seguintes', () => {
    const p3 = invoicePeriodForPurchase('2026-11-20', itau, 2);
    expect(p3).toEqual({ refMonth: '2027-01-01', closingDate: '2027-01-25', dueDate: '2027-02-05' });
  });
});

describe('situação da fatura', () => {
  const period = { closingDate: '2026-11-05', dueDate: '2026-11-12' };
  it('aberta antes do fechamento', () => {
    expect(invoiceStatus(period, 1000, 0, '2026-11-04', nubank)).toBe('OPEN');
  });
  it('fechada no dia do fechamento (compras do dia vão para a próxima)', () => {
    expect(invoiceStatus(period, 1000, 0, '2026-11-05', nubank)).toBe('CLOSED');
  });
  it('atrasada após o vencimento', () => {
    expect(invoiceStatus(period, 1000, 400, '2026-11-13', nubank)).toBe('OVERDUE');
  });
  it('paga', () => {
    expect(invoiceStatus(period, 1000, 1000, '2026-11-13', nubank)).toBe('PAID');
  });
});

describe('total da fatura', () => {
  it('estorno abate do total e pagamento parcial deixa restante', () => {
    const r = invoiceTotals(
      [
        { type: 'EXPENSE', amount: 10000 },
        { type: 'INCOME', amount: 1500 },
      ],
      [{ amount: 3000 }],
    );
    expect(r).toEqual({ total: 8500, paid: 3000, remaining: 5500 });
  });
});
