import type { DateStr } from '../lib/dates';

/** Lançamento lido de um arquivo OFX (fatura de cartão). Valores em centavos, sempre positivos. */
export interface OfxEntry {
  /** Posição no arquivo; serve de chave entre a prévia e a importação. */
  index: number;
  fitId: string;
  /** Texto original do arquivo (MEMO ou NAME). */
  memo: string;
  /** Nome sem o sufixo " - Parcela k/N". */
  name: string;
  date: DateStr;
  amount: number;
  /** EXPENSE = compra (débito), INCOME = estorno/crédito. */
  type: 'EXPENSE' | 'INCOME';
  installment: { number: number; total: number } | null;
  /** Pagamento da fatura anterior ("Pagamento recebido"): não é item da fatura. */
  isPayment: boolean;
}

export interface OfxStatement {
  start: DateStr | null;
  end: DateStr | null;
  entries: OfxEntry[];
}

/** Valor de uma tag SGML/XML (`<TAG>valor` ou `<TAG>valor</TAG>`). */
function tag(block: string, name: string): string | null {
  const m = new RegExp(`<${name}>([^<\\r\\n]*)`, 'i').exec(block);
  return m ? m[1].trim() : null;
}

/** "20261118000000[-3:BRT]" -> "2026-11-18". */
function ofxDate(v: string | null): DateStr | null {
  const m = v ? /^(\d{4})(\d{2})(\d{2})/.exec(v) : null;
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

/** "-1.234,56" / "-1234.56" -> centavos com sinal, sem passar por float. */
export function ofxAmount(v: string): number {
  let s = v.trim().replace(/\s/g, '');
  const neg = s.startsWith('-');
  s = s.replace(/^[+-]/, '');
  // Vírgula decimal (e ponto de milhar, se houver).
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.');
  if (!/^\d+(\.\d+)?$/.test(s)) throw new Error(`Valor inválido: ${v}`);
  const [int, frac = ''] = s.split('.');
  const cents = Number(int) * 100 + Number((frac + '00').slice(0, 2));
  return neg ? -cents : cents;
}

const INSTALLMENT_RE = /\s*-?\s*parcela\s+(\d{1,3})\s*\/\s*(\d{1,3})\s*$/i;
const PAYMENT_RE = /^pagamento (recebido|efetuado|de fatura)/i;

export function splitInstallment(memo: string): { name: string; installment: OfxEntry['installment'] } {
  const m = INSTALLMENT_RE.exec(memo);
  if (!m) return { name: memo.trim(), installment: null };
  const number = Number(m[1]);
  const total = Number(m[2]);
  if (number < 1 || total < 2 || number > total) return { name: memo.trim(), installment: null };
  return { name: memo.slice(0, m.index).trim() || memo.trim(), installment: { number, total } };
}

/** Lê os lançamentos de um OFX (1.x SGML ou 2.x XML). */
export function parseOfx(text: string): OfxStatement {
  if (!/<OFX>/i.test(text)) throw new Error('Arquivo não parece ser um OFX');
  const blocks = text.match(/<STMTTRN>[\s\S]*?(?=<\/STMTTRN>|<STMTTRN>|<\/BANKTRANLIST>)/gi) ?? [];
  const entries: OfxEntry[] = [];
  for (const block of blocks) {
    const rawAmount = tag(block, 'TRNAMT');
    const date = ofxDate(tag(block, 'DTPOSTED'));
    if (!rawAmount || !date) continue;
    const signed = ofxAmount(rawAmount);
    if (signed === 0) continue;
    const memo = tag(block, 'MEMO') || tag(block, 'NAME') || 'Sem descrição';
    const fitId = tag(block, 'FITID') || `${date}:${signed}:${memo}`;
    const { name, installment } = splitInstallment(memo);
    const type = signed < 0 ? 'EXPENSE' : 'INCOME';
    entries.push({
      index: entries.length,
      fitId,
      memo,
      name,
      date,
      amount: Math.abs(signed),
      type,
      installment,
      isPayment: type === 'INCOME' && PAYMENT_RE.test(memo),
    });
  }
  return { start: ofxDate(tag(text, 'DTSTART')), end: ofxDate(tag(text, 'DTEND')), entries };
}

/** Lançamento já existente na fatura, para conciliar. */
export interface ExistingItem {
  id: string;
  type: string;
  amount: number;
  date: DateStr;
  externalId: string | null;
  installmentNumber: number | null;
  installmentTotal: number | null;
}

export type MatchReason = 'externalId' | 'amountDate' | 'installment';

/**
 * Concilia os lançamentos do arquivo com os da fatura. Cada lançamento existente casa no máximo uma vez.
 * Ordem: mesmo id da operação > mesmo valor e data > (parcelas) mesmo valor e número/total da parcela.
 * O nome não importa.
 */
export function matchEntries<T extends ExistingItem>(
  entries: OfxEntry[],
  existing: T[],
): Map<number, { item: T; reason: MatchReason }> {
  const used = new Set<string>();
  const out = new Map<number, { item: T; reason: MatchReason }>();
  const pending = () => entries.filter((e) => !e.isPayment && !out.has(e.index));
  const pass = (reason: MatchReason, ok: (e: OfxEntry, x: T) => boolean) => {
    for (const e of pending()) {
      const x = existing.find((x) => !used.has(x.id) && x.type === e.type && ok(e, x));
      if (x) {
        used.add(x.id);
        out.set(e.index, { item: x, reason });
      }
    }
  };
  pass('externalId', (e, x) => x.externalId === e.fitId && sameInstallment(e, x));
  pass('amountDate', (e, x) => x.amount === e.amount && x.date === e.date);
  pass(
    'installment',
    (e, x) =>
      !!e.installment &&
      x.amount === e.amount &&
      x.installmentNumber === e.installment.number &&
      x.installmentTotal === e.installment.total,
  );
  return out;
}

/** Com o mesmo FITID em todas as parcelas, a parcela precisa bater (quando as duas pontas têm). */
function sameInstallment(e: OfxEntry, x: ExistingItem): boolean {
  if (!e.installment || x.installmentNumber == null) return true;
  return e.installment.number === x.installmentNumber && e.installment.total === x.installmentTotal;
}
