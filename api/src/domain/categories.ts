import { addDays, addMonths, endOfMonth, startOfMonth, toDate, type DateStr } from '../lib/dates';

/** Dados mínimos de um lançamento para o relatório por categoria. */
export interface CategoryTx {
  id: string;
  type: 'INCOME' | 'EXPENSE' | 'TRANSFER';
  status: 'PENDING' | 'PAID';
  amount: number;
  date: DateStr;
  cardId: string | null;
  categoryId: string | null;
  /** Pagamento de fatura: é quitação de dívida, não gasto (as compras já contam). */
  paysInvoiceId: string | null;
  /** Vencimento da fatura em que a compra no cartão entrou. */
  invoiceDueDate: DateStr | null;
}

export type CategoryKind = 'EXPENSE' | 'INCOME';

export interface CategoryOptions {
  kind: CategoryKind;
  /** purchase: compra no cartão na data da compra; payment: no vencimento da fatura. */
  cardDate: 'purchase' | 'payment';
  /** projected: tudo (inclui pendentes/agendados); realized: só o que já aconteceu. */
  basis: 'projected' | 'realized';
  today: DateStr;
}

/**
 * Quanto o lançamento conta no relatório: positivo soma, negativo abate (estorno no cartão),
 * null = não entra. Transferências e pagamentos de fatura nunca entram.
 */
export function categoryAmount(tx: CategoryTx, opts: CategoryOptions): number | null {
  if (tx.type === 'TRANSFER' || tx.paysInvoiceId) return null;

  let sign: number;
  if (opts.kind === 'EXPENSE') {
    if (tx.type === 'EXPENSE') sign = 1;
    else if (tx.type === 'INCOME' && tx.cardId) sign = -1; // estorno abate o gasto
    else return null;
  } else {
    if (tx.type !== 'INCOME' || tx.cardId) return null;
    sign = 1;
  }

  if (opts.basis === 'realized') {
    // No cartão, a compra já aconteceu quando a data chega; na conta, quando está paga.
    if (tx.cardId ? tx.date > opts.today : tx.status !== 'PAID') return null;
  }
  return sign * tx.amount;
}

/** Dia em que o lançamento cai no relatório. */
export function reportDate(tx: CategoryTx, cardDate: CategoryOptions['cardDate']): DateStr {
  return cardDate === 'payment' && tx.cardId && tx.invoiceDueDate ? tx.invoiceDueDate : tx.date;
}

/** true se o intervalo vai do dia 1 até o último dia de um mês. */
function wholeMonths(from: DateStr, to: DateStr): number | null {
  if (from !== startOfMonth(from) || to !== endOfMonth(to)) return null;
  const [fy, fm] = from.split('-').map(Number);
  const [ty, tm] = to.split('-').map(Number);
  return (ty - fy) * 12 + (tm - fm) + 1;
}

/**
 * Intervalo `steps` períodos antes (mesmo tamanho). Meses inteiros andam por mês
 * (fevereiro e meses de 30/31 dias ficam certos); outros intervalos andam por dias.
 */
export function shiftWindow(from: DateStr, to: DateStr, steps: number): [DateStr, DateStr] {
  const months = wholeMonths(from, to);
  if (months !== null) {
    const start = addMonths(from, months * steps);
    return [start, endOfMonth(addMonths(start, months - 1))];
  }
  const days = Math.round((toDate(to).getTime() - toDate(from).getTime()) / 86_400_000) + 1;
  return [addDays(from, days * steps), addDays(to, days * steps)];
}

interface Sum {
  total: number;
  count: number;
}

/** Soma por categoria (null = sem categoria) dentro do intervalo. */
export function sumByCategory(
  txs: CategoryTx[],
  from: DateStr,
  to: DateStr,
  opts: CategoryOptions,
): Map<string | null, Sum> {
  const out = new Map<string | null, Sum>();
  for (const tx of txs) {
    const date = reportDate(tx, opts.cardDate);
    if (date < from || date > to) continue;
    const amount = categoryAmount(tx, opts);
    if (amount === null) continue;
    const s = out.get(tx.categoryId) ?? { total: 0, count: 0 };
    s.total += amount;
    s.count += 1;
    out.set(tx.categoryId, s);
  }
  return out;
}

export interface CategoryInfo {
  name: string;
  color: string | null;
  icon: string | null;
}

export interface CategoryRow {
  id: string | null;
  name: string;
  color: string | null;
  icon: string | null;
  total: number;
  count: number;
  /** Fatia do total do período (0 a 1). */
  share: number;
  /** Mesmo tamanho de período, imediatamente antes. */
  previous: number;
  /** Média dos 3 períodos anteriores. */
  average: number;
}

export interface CategoryReport {
  kind: CategoryKind;
  from: DateStr;
  to: DateStr;
  previousFrom: DateStr;
  previousTo: DateStr;
  total: number;
  count: number;
  previousTotal: number;
  averageTotal: number;
  categories: CategoryRow[];
}

const AVERAGE_PERIODS = 3;

export function buildCategoryReport(params: {
  txs: CategoryTx[];
  categories: Map<string, CategoryInfo>;
  from: DateStr;
  to: DateStr;
  opts: CategoryOptions;
}): CategoryReport {
  const { txs, categories, from, to, opts } = params;
  const current = sumByCategory(txs, from, to, opts);
  const past = Array.from({ length: AVERAGE_PERIODS }, (_, i) => {
    const [f, t] = shiftWindow(from, to, -(i + 1));
    return sumByCategory(txs, f, t, opts);
  });
  const [previousFrom, previousTo] = shiftWindow(from, to, -1);

  const ids = new Set<string | null>([...current.keys(), ...past[0].keys()]);
  const total = [...current.values()].reduce((s, v) => s + v.total, 0);
  const sumOf = (m: Map<string | null, Sum>) => [...m.values()].reduce((s, v) => s + v.total, 0);

  const rows: CategoryRow[] = [...ids].map((id) => {
    const info = id ? categories.get(id) : undefined;
    const cur = current.get(id) ?? { total: 0, count: 0 };
    const avg = past.reduce((s, m) => s + (m.get(id)?.total ?? 0), 0) / AVERAGE_PERIODS;
    return {
      id,
      name: info?.name ?? 'Sem categoria',
      color: info?.color ?? null,
      icon: info?.icon ?? null,
      total: cur.total,
      count: cur.count,
      share: total > 0 && cur.total > 0 ? cur.total / total : 0,
      previous: past[0].get(id)?.total ?? 0,
      average: Math.round(avg),
    };
  });
  rows.sort((a, b) => b.total - a.total || b.previous - a.previous || a.name.localeCompare(b.name));

  return {
    kind: opts.kind,
    from,
    to,
    previousFrom,
    previousTo,
    total,
    count: [...current.values()].reduce((s, v) => s + v.count, 0),
    previousTotal: sumOf(past[0]),
    averageTotal: Math.round(past.reduce((s, m) => s + sumOf(m), 0) / AVERAGE_PERIODS),
    categories: rows,
  };
}

/** Total mês a mês (calendário) de uma categoria (`undefined` = todas), terminando no mês de `endMonth`. */
export function monthlyHistory(
  txs: CategoryTx[],
  categoryId: string | null | undefined,
  endMonth: DateStr,
  months: number,
  opts: CategoryOptions,
): { month: DateStr; total: number }[] {
  const out: { month: DateStr; total: number }[] = [];
  for (let i = months - 1; i >= 0; i--) {
    const start = startOfMonth(addMonths(endMonth, -i));
    const sums = sumByCategory(txs, start, endOfMonth(start), opts);
    const total =
      categoryId === undefined
        ? [...sums.values()].reduce((s, v) => s + v.total, 0)
        : (sums.get(categoryId)?.total ?? 0);
    out.push({ month: start, total });
  }
  return out;
}
