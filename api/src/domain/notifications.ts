import { z } from 'zod';
import { addDays, isDateStr, toDate, type DateStr } from '../lib/dates';

/** Notificação de banco como o celular envia. */
export interface BankNotification {
  app: string;
  appName?: string | null;
  title?: string | null;
  text: string;
  /** ISO com fuso (ex.: 2026-11-19T18:42:10-03:00). */
  postedAt: string;
}

export interface PromptContext {
  today: DateStr;
  accounts: { id: string; name: string }[];
  cards: { id: string; name: string; lastDigits: string | null; paymentAccountName: string }[];
  categories: { EXPENSE: { id: string; name: string }[]; INCOME: { id: string; name: string }[] };
  /** Lançamentos recentes já categorizados (ensinam o jeito do usuário). */
  history: { description: string; merchant: string | null; categoryId: string }[];
}

const SYSTEM_PROMPT = `Você é o extrator de lançamentos financeiros de um app pessoal de finanças.
Recebe UMA notificação de um app de banco e devolve SOMENTE um JSON válido, sem texto antes ou depois, sem markdown.

Tarefa:
1. Decidir se a notificação é uma movimentação de dinheiro já realizada (compra, débito, Pix/TED enviado ou recebido, depósito, estorno).
   NÃO são movimentações: propaganda, oferta de crédito, "fatura fechou", "fatura vence amanhã", lembrete de boleto, código de segurança, compra NEGADA, aviso de login. Para essas, "isTransaction": false.
2. Se for movimentação, extrair os campos e escolher a conta ou o cartão e a categoria, usando apenas os ids fornecidos.

Regras:
- "amount" em centavos, inteiro e positivo (R$ 87,40 -> 8740). O sentido vai em "type".
- "type": "EXPENSE" (saiu dinheiro, inclusive compra no cartão), "INCOME" (entrou dinheiro) ou "TRANSFER" (só quando o texto deixar claro que é entre contas do próprio usuário).
- "channel": "CARD" (compra/estorno no cartão de crédito), "PIX", "DEBIT" (débito em conta, boleto pago) ou "OTHER".
- Compra no cartão: preencher "cardId" pelo final do cartão; "accountId" null. Se o final não bater com nenhum cartão, "cardId" null.
- Movimentação em conta: preencher "accountId" pela conta do banco do app que gerou a notificação (compare o nome do app com o nome das contas); "cardId" null.
- Estorno no cartão: "type": "INCOME", "channel": "CARD".
- "date": data da movimentação (AAAA-MM-DD). Se o texto não trouxer data, usar a data de "postedAt".
- "merchant": nome do estabelecimento ou da pessoa como aparece no texto, sem o final do cartão.
- "description": descrição curta e legível para o lançamento (ex.: "Posto Shell"), em português, primeira letra maiúscula, sem valores.
- "installments": número de parcelas se o texto disser (ex.: "em 3x"), senão null. "amount" é sempre o valor TOTAL da compra.
- "categoryId": escolher entre as categorias do tipo certo (despesa para EXPENSE, receita para INCOME). Preferir a categoria usada nos exemplos do histórico para o mesmo estabelecimento ou para um parecido. Se nenhuma servir com segurança, null.
- "confidence": de 0 a 1, sua confiança na categoria.
- Nunca invente ids. Use null quando não souber.

Formato da resposta:
{
  "isTransaction": boolean,
  "reason": string | null,
  "type": "EXPENSE" | "INCOME" | "TRANSFER" | null,
  "channel": "CARD" | "PIX" | "DEBIT" | "OTHER" | null,
  "amount": integer | null,
  "date": "AAAA-MM-DD" | null,
  "merchant": string | null,
  "description": string | null,
  "accountId": string | null,
  "cardId": string | null,
  "installments": integer | null,
  "categoryId": string | null,
  "confidence": number | null
}
("reason": só quando isTransaction=false, dizendo por que não é movimentação.)`;

/** Mensagens enviadas à IA: instruções fixas + dados do usuário + a notificação. */
export function buildPrompt(n: BankNotification, ctx: PromptContext): { system: string; user: string } {
  const data = {
    today: ctx.today,
    accounts: ctx.accounts,
    cards: ctx.cards,
    categories: ctx.categories,
  };
  const user = [
    'Dados do usuário:',
    JSON.stringify(data, null, 1),
    '',
    'Exemplos do histórico (como o usuário costuma categorizar):',
    JSON.stringify(ctx.history),
    '',
    'Notificação:',
    JSON.stringify({ app: n.app, appName: n.appName ?? null, title: n.title ?? null, text: n.text, postedAt: n.postedAt }, null, 1),
  ].join('\n');
  return { system: SYSTEM_PROMPT, user };
}

const nullableStr = z.string().nullish().transform((v) => (v && v.trim() ? v.trim() : null));
const aiSchema = z.object({
  isTransaction: z.boolean(),
  reason: nullableStr,
  type: z.enum(['EXPENSE', 'INCOME', 'TRANSFER']).nullish(),
  channel: z.enum(['CARD', 'PIX', 'DEBIT', 'OTHER']).nullish().catch(null),
  amount: z.number().nullish(),
  date: z.string().nullish(),
  merchant: nullableStr,
  description: nullableStr,
  accountId: nullableStr,
  cardId: nullableStr,
  installments: z.number().nullish(),
  categoryId: nullableStr,
  confidence: z.number().nullish(),
});

export interface ParsedNotification {
  isTransaction: boolean;
  reason: string | null;
  type: 'EXPENSE' | 'INCOME' | 'TRANSFER' | null;
  channel: 'CARD' | 'PIX' | 'DEBIT' | 'OTHER' | null;
  amount: number | null;
  date: DateStr | null;
  merchant: string | null;
  description: string | null;
  accountId: string | null;
  cardId: string | null;
  installments: number | null;
  categoryId: string | null;
  confidence: number | null;
}

/**
 * Valida a resposta da IA. Ids que não existem viram null (a IA não pode inventar), a data
 * cai para a da notificação se vier inválida, e uma movimentação sem valor ou tipo não serve.
 */
export function parseAiResult(raw: unknown, ctx: PromptContext, fallbackDate: DateStr): ParsedNotification {
  const r = aiSchema.parse(raw);
  const has = (list: { id: string }[], id: string | null) => (id && list.some((x) => x.id === id) ? id : null);
  const type = r.type ?? null;
  const cats = type === 'INCOME' ? ctx.categories.INCOME : type === 'EXPENSE' ? ctx.categories.EXPENSE : [];
  const amount = r.amount != null && Number.isFinite(r.amount) ? Math.round(Math.abs(r.amount)) : null;
  let cardId = has(ctx.cards, r.cardId);
  const accountId = cardId ? null : has(ctx.accounts, r.accountId);
  if (r.channel !== 'CARD' && cardId && accountId) cardId = null;
  const installments = r.installments != null && r.installments >= 2 && r.installments <= 360 ? Math.round(r.installments) : null;
  const parsed: ParsedNotification = {
    isTransaction: r.isTransaction,
    reason: r.reason,
    type,
    channel: r.channel ?? null,
    amount,
    date: r.date && isDateStr(r.date) ? r.date : fallbackDate,
    merchant: r.merchant,
    description: r.description?.slice(0, 200) ?? r.merchant?.slice(0, 200) ?? null,
    accountId,
    cardId,
    installments,
    categoryId: has(cats, r.categoryId),
    confidence: r.confidence != null ? Math.max(0, Math.min(1, r.confidence)) : null,
  };
  if (parsed.isTransaction && (!parsed.amount || !parsed.type)) {
    return { ...parsed, isTransaction: false, reason: parsed.reason ?? 'A IA não achou valor ou tipo na notificação' };
  }
  return parsed;
}

/** Dia (no fuso do app) em que a notificação chegou. */
export function localDate(iso: string, timeZone = process.env.APP_TZ || 'America/Sao_Paulo'): DateStr {
  const d = new Date(iso);
  const fmt = new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' });
  const get = (type: string) => fmt.formatToParts(d).find((p) => p.type === type)!.value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

/** Lançamento real considerado na comparação. */
export interface MatchTx {
  id: string;
  type: 'INCOME' | 'EXPENSE' | 'TRANSFER';
  status: 'PENDING' | 'PAID';
  amount: number;
  date: DateStr;
  accountId: string | null;
  cardId: string | null;
}

export type MatchResult =
  | { action: 'pay'; txId: string }
  | { action: 'exists'; txId: string }
  | { action: 'suggest'; reason?: string };

/** Até quantos dias antes/depois um pendente em conta pode ser o mesmo (conta paga antes ou depois do vencimento). */
export const PENDING_WINDOW_DAYS = 10;

const daysBetween = (a: DateStr, b: DateStr) => Math.round(Math.abs(toDate(a).getTime() - toDate(b).getTime()) / 86_400_000);

/**
 * Procura o lançamento que a notificação descreve (mesmo tipo e valor exato).
 * - Cartão: mesma compra até 1 dia de diferença → já existe (compra no cartão já nasce paga).
 * - Conta: pendente no mesmo dia (±1) → dar baixa; pago no mesmo dia → já existe;
 *   senão, pendente até 10 dias de distância (o mais perto) → dar baixa.
 * - Dois candidatos igualmente perto: não escolhe sozinho, vira sugestão.
 * `linked` = lançamentos já ligados a outra notificação (dois cafés iguais no mesmo dia não batem no mesmo).
 */
export function matchNotification(p: ParsedNotification, txs: MatchTx[], linked: Set<string>): MatchResult {
  if (!p.isTransaction || !p.amount || !p.type || !p.date) return { action: 'suggest' };
  const date = p.date;
  const same = txs.filter((t) => !linked.has(t.id) && t.type === p.type && t.amount === p.amount);
  const onCard = p.channel === 'CARD' || !!p.cardId;

  const closest = (list: MatchTx[]): MatchResult | MatchTx => {
    const sorted = [...list].sort((a, b) => daysBetween(a.date, date) - daysBetween(b.date, date));
    if (sorted.length > 1 && daysBetween(sorted[0].date, date) === daysBetween(sorted[1].date, date)) {
      return { action: 'suggest', reason: 'Mais de um lançamento igual; escolha manualmente' };
    }
    return sorted[0];
  };

  if (onCard) {
    const list = same.filter((t) => t.cardId && (!p.cardId || t.cardId === p.cardId) && daysBetween(t.date, date) <= 1);
    if (list.length === 0) return { action: 'suggest' };
    const hit = closest(list);
    return 'action' in hit ? hit : { action: 'exists', txId: hit.id };
  }

  const inAccount = same.filter((t) => !t.cardId && (!p.accountId || t.accountId === p.accountId));
  const near = inAccount.filter((t) => daysBetween(t.date, date) <= 1);
  const nearPending = near.filter((t) => t.status === 'PENDING');
  if (nearPending.length) {
    const hit = closest(nearPending);
    return 'action' in hit ? hit : { action: 'pay', txId: hit.id };
  }
  const nearPaid = near.filter((t) => t.status === 'PAID');
  if (nearPaid.length) {
    // Já está pago: tanto faz qual dos iguais, nada vai ser alterado.
    const first = [...nearPaid].sort((a, b) => daysBetween(a.date, date) - daysBetween(b.date, date))[0];
    return { action: 'exists', txId: first.id };
  }

  const window = inAccount.filter(
    (t) => t.status === 'PENDING' && t.date >= addDays(date, -PENDING_WINDOW_DAYS) && t.date <= addDays(date, PENDING_WINDOW_DAYS),
  );
  if (window.length) {
    const hit = closest(window);
    return 'action' in hit ? hit : { action: 'pay', txId: hit.id };
  }
  return { action: 'suggest' };
}
