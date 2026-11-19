/** Lançamento com o vínculo de contrapartida (origem ↔ contrapartida). */
export interface CounterpartLinked {
  id: string;
  counterpartOfId: string | null;
}

/**
 * Ids dos lançamentos que fazem parte de um par origem + contrapartida (os dois lados).
 * Usado para tirar os pares dos totais quando o usuário não quer vê-los: juntos eles se anulam,
 * mas inflam receitas e despesas.
 */
export function counterpartPairIds(txs: CounterpartLinked[]): Set<string> {
  const ids = new Set(txs.map((t) => t.id));
  const out = new Set<string>();
  for (const t of txs) {
    if (t.counterpartOfId && ids.has(t.counterpartOfId)) {
      out.add(t.id);
      out.add(t.counterpartOfId);
    }
  }
  return out;
}

export interface CounterpartTotals {
  /** Contrapartidas ainda pendentes (falta receber de volta, ou falta pagar). */
  pending: number;
  /** Contrapartidas já pagas/recebidas. */
  settled: number;
  count: number;
}

/** Totais das contrapartidas de um tipo (INCOME = a receber de volta; EXPENSE = a devolver). */
export function counterpartTotals(items: { amount: number; status: 'PENDING' | 'PAID' }[]): CounterpartTotals {
  let pending = 0;
  let settled = 0;
  for (const i of items) {
    if (i.status === 'PAID') settled += i.amount;
    else pending += i.amount;
  }
  return { pending, settled, count: items.length };
}
