import { describe, expect, it } from 'vitest';
import { matchEntries, ofxAmount, parseOfx, splitInstallment, type ExistingItem } from '../src/domain/ofx';

const trn = (type: string, date: string, amt: string, fitId: string, memo: string) => `
<STMTTRN>
<TRNTYPE>${type}</TRNTYPE>
<DTPOSTED>${date}000000[-3:BRT]</DTPOSTED>
<TRNAMT>${amt}</TRNAMT>
<FITID>${fitId}</FITID>
<MEMO>${memo}</MEMO>
</STMTTRN>`;

const sample = `OFXHEADER:100
DATA:OFXSGML
<OFX><CREDITCARDMSGSRSV1><CCSTMTTRNRS><CCSTMTRS><BANKTRANLIST>
<DTSTART>20261103000000[-3:BRT]</DTSTART>
<DTEND>20261203000000[-3:BRT]</DTEND>
${trn('DEBIT', '20261118', '-16.20', 'a1', '99app *99app')}
${trn('DEBIT', '20261114', '-106.68', 'a2', 'Pit Stop-Moto Service - Parcela 1/3')}
${trn('CREDIT', '20261106', '3312.05', 'a3', 'Pagamento recebido')}
${trn('CREDIT', '20261105', '21.09', 'a4', 'Estorno de compra (99 Food)')}
${trn('DEBIT', '20261105', '-21.09', 'a4', '99food *P Gonzalez da')}
${trn('DEBIT', '20261103', '-249.25', 'a5', 'Maiscor Tintas - Parcela 3/4')}
</BANKTRANLIST></CCSTMTRS></CCSTMTTRNRS></CREDITCARDMSGSRSV1></OFX>`;

describe('ofxAmount', () => {
  it('converte sem erro de ponto flutuante', () => {
    expect(ofxAmount('-16.20')).toBe(-1620);
    expect(ofxAmount('3312.05')).toBe(331205);
    expect(ofxAmount('-1.234,56')).toBe(-123456);
    expect(ofxAmount('10')).toBe(1000);
    expect(ofxAmount('0.1')).toBe(10);
  });
});

describe('splitInstallment', () => {
  it('separa o sufixo de parcela', () => {
    expect(splitInstallment('Maiscor Tintas - Parcela 3/4')).toEqual({
      name: 'Maiscor Tintas',
      installment: { number: 3, total: 4 },
    });
    expect(splitInstallment('iFood - NuPay')).toEqual({ name: 'iFood - NuPay', installment: null });
  });
});

describe('parseOfx', () => {
  const stmt = parseOfx(sample);

  it('lê período e lançamentos', () => {
    expect(stmt.start).toBe('2026-11-03');
    expect(stmt.end).toBe('2026-12-03');
    expect(stmt.entries).toHaveLength(6);
    expect(stmt.entries[0]).toMatchObject({ date: '2026-11-18', amount: 1620, type: 'EXPENSE', fitId: 'a1' });
  });

  it('marca pagamento da fatura e estorno', () => {
    expect(stmt.entries[2]).toMatchObject({ isPayment: true, type: 'INCOME' });
    expect(stmt.entries[3]).toMatchObject({ isPayment: false, type: 'INCOME', amount: 2109 });
  });

  it('recusa arquivo que não é OFX', () => {
    expect(() => parseOfx('data;valor\n1;2')).toThrow();
  });
});

describe('matchEntries', () => {
  const stmt = parseOfx(sample);
  const item = (over: Partial<ExistingItem>): ExistingItem => ({
    id: 'x',
    type: 'EXPENSE',
    amount: 0,
    date: '2026-11-01',
    externalId: null,
    installmentNumber: null,
    installmentTotal: null,
    ...over,
  });

  it('concilia por valor e data mesmo com nome diferente', () => {
    const m = matchEntries(stmt.entries, [item({ id: 't1', amount: 1620, date: '2026-11-18' })]);
    expect(m.get(0)).toMatchObject({ item: { id: 't1' }, reason: 'amountDate' });
    expect(m.size).toBe(1);
  });

  it('concilia por id da operação antes de valor/data', () => {
    const m = matchEntries(stmt.entries, [
      item({ id: 'same-date', amount: 1620, date: '2026-11-18' }),
      item({ id: 'by-id', amount: 1500, date: '2026-11-10', externalId: 'a1' }),
    ]);
    expect(m.get(0)?.item.id).toBe('by-id');
  });

  it('estorno e compra com o mesmo FITID casam pelo tipo', () => {
    const m = matchEntries(stmt.entries, [
      item({ id: 'buy', amount: 2109, externalId: 'a4' }),
      item({ id: 'refund', type: 'INCOME', amount: 2109, externalId: 'a4' }),
    ]);
    expect(m.get(3)?.item.id).toBe('refund');
    expect(m.get(4)?.item.id).toBe('buy');
  });

  it('parcela lançada no app com outra data casa pelo número da parcela', () => {
    const m = matchEntries(stmt.entries, [
      item({ id: 'p3', amount: 24925, date: '2026-09-02', installmentNumber: 3, installmentTotal: 4 }),
    ]);
    expect(m.get(5)).toMatchObject({ item: { id: 'p3' }, reason: 'installment' });
  });

  it('cada lançamento do app casa uma vez só', () => {
    const twice = parseOfx(sample.replace('</BANKTRANLIST>', `${trn('DEBIT', '20261118', '-16.20', 'b1', '99app *99app')}</BANKTRANLIST>`));
    const m = matchEntries(twice.entries, [item({ id: 't1', amount: 1620, date: '2026-11-18' })]);
    expect(m.size).toBe(1);
  });

  it('nunca concilia o pagamento da fatura', () => {
    const m = matchEntries(stmt.entries, [item({ id: 'p', type: 'INCOME', amount: 331205, date: '2026-11-06' })]);
    expect(m.size).toBe(0);
  });
});
