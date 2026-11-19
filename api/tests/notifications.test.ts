import { describe, expect, it } from 'vitest';
import {
  buildPrompt,
  localDate,
  matchNotification,
  parseAiResult,
  type MatchTx,
  type ParsedNotification,
  type PromptContext,
} from '../src/domain/notifications';

const ctx: PromptContext = {
  today: '2026-11-19',
  accounts: [
    { id: 'acc_nu', name: 'Nubank conta' },
    { id: 'acc_itau', name: 'Itaú' },
  ],
  cards: [{ id: 'card_roxo', name: 'Roxinho', lastDigits: '4821', paymentAccountName: 'Nubank conta' }],
  categories: {
    EXPENSE: [{ id: 'cat_comb', name: 'Combustível' }],
    INCOME: [{ id: 'cat_reemb', name: 'Reembolsos' }],
  },
  history: [{ description: 'Posto Ipiranga', merchant: null, categoryId: 'cat_comb' }],
};

const parsed = (p: Partial<ParsedNotification>): ParsedNotification => ({
  isTransaction: true,
  reason: null,
  type: 'EXPENSE',
  channel: 'PIX',
  amount: 5000,
  date: '2026-11-19',
  merchant: null,
  description: 'x',
  accountId: 'acc_nu',
  cardId: null,
  installments: null,
  categoryId: null,
  confidence: null,
  ...p,
});

const tx = (p: Partial<MatchTx>): MatchTx => ({
  id: 't',
  type: 'EXPENSE',
  status: 'PENDING',
  amount: 5000,
  date: '2026-11-19',
  accountId: 'acc_nu',
  cardId: null,
  ...p,
});

describe('prompt', () => {
  it('leva categorias, cartões, histórico e a notificação', () => {
    const { system, user } = buildPrompt(
      { app: 'com.nu.production', appName: 'Nubank', title: 'Compra', text: 'R$ 87,40 final 4821', postedAt: '2026-11-19T18:00:00-03:00' },
      ctx,
    );
    expect(system).toContain('SOMENTE um JSON');
    expect(user).toContain('"lastDigits": "4821"');
    expect(user).toContain('Posto Ipiranga');
    expect(user).toContain('R$ 87,40 final 4821');
  });
});

describe('resposta da IA', () => {
  it('ids inventados viram null e a categoria tem que ser do tipo certo', () => {
    const r = parseAiResult(
      { isTransaction: true, type: 'EXPENSE', channel: 'CARD', amount: 8740, date: '2026-11-19', cardId: 'card_falso', categoryId: 'cat_reemb' },
      ctx,
      '2026-11-19',
    );
    expect(r.cardId).toBeNull();
    expect(r.categoryId).toBeNull();
  });

  it('data inválida cai para a da notificação; sem valor não é movimentação', () => {
    const r = parseAiResult({ isTransaction: true, type: 'EXPENSE', amount: 100, date: 'ontem' }, ctx, '2026-11-18');
    expect(r.date).toBe('2026-11-18');
    const s = parseAiResult({ isTransaction: true, type: 'EXPENSE', amount: null }, ctx, '2026-11-18');
    expect(s.isTransaction).toBe(false);
  });

  it('não-movimentação passa direto', () => {
    const r = parseAiResult({ isTransaction: false, reason: 'Fatura fechou' }, ctx, '2026-11-18');
    expect(r).toMatchObject({ isTransaction: false, reason: 'Fatura fechou' });
  });

  it('dia da notificação no fuso de São Paulo', () => {
    expect(localDate('2026-11-20T01:30:00Z', 'America/Sao_Paulo')).toBe('2026-11-19');
  });
});

describe('comparação com os lançamentos', () => {
  it('pendente no mesmo dia: dá baixa', () => {
    expect(matchNotification(parsed({}), [tx({ id: 'a' })], new Set())).toEqual({ action: 'pay', txId: 'a' });
  });

  it('pago no mesmo dia: já existe', () => {
    expect(matchNotification(parsed({}), [tx({ id: 'a', status: 'PAID' })], new Set())).toEqual({
      action: 'exists',
      txId: 'a',
    });
  });

  it('conta paga antes do vencimento: pendente até 10 dias depois também recebe baixa', () => {
    const r = matchNotification(parsed({ date: '2026-11-07' }), [tx({ id: 'luz', date: '2026-11-10' })], new Set());
    expect(r).toEqual({ action: 'pay', txId: 'luz' });
  });

  it('valor diferente ou outra conta: vira sugestão', () => {
    expect(matchNotification(parsed({}), [tx({ amount: 5001 })], new Set()).action).toBe('suggest');
    expect(matchNotification(parsed({}), [tx({ accountId: 'acc_itau' })], new Set()).action).toBe('suggest');
  });

  it('cartão: compra igual até 1 dia de diferença já existe; nunca dá baixa', () => {
    const p = parsed({ channel: 'CARD', cardId: 'card_roxo', accountId: null });
    const t = tx({ id: 'c', cardId: 'card_roxo', accountId: null, status: 'PAID', date: '2026-11-18' });
    expect(matchNotification(p, [t], new Set())).toEqual({ action: 'exists', txId: 'c' });
    expect(matchNotification(p, [{ ...t, date: '2026-11-15' }], new Set()).action).toBe('suggest');
  });

  it('dois cafés iguais: o segundo não bate no lançamento já ligado ao primeiro', () => {
    const t = tx({ id: 'cafe', status: 'PAID' });
    expect(matchNotification(parsed({}), [t], new Set(['cafe'])).action).toBe('suggest');
  });

  it('dois pendentes igualmente perto: não escolhe sozinho', () => {
    const r = matchNotification(parsed({}), [tx({ id: 'a' }), tx({ id: 'b' })], new Set());
    expect(r.action).toBe('suggest');
  });
});
