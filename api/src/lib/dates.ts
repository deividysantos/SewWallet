/**
 * Datas de calendário como string 'YYYY-MM-DD' (sem hora e sem fuso).
 * No banco ficam em colunas DATE; o Prisma as entrega como Date à meia-noite UTC.
 */
export type DateStr = string;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function isDateStr(value: string): boolean {
  if (!DATE_RE.test(value)) return false;
  const d = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

export function toDate(s: DateStr): Date {
  return new Date(`${s}T00:00:00.000Z`);
}

export function fromDate(d: Date): DateStr {
  return d.toISOString().slice(0, 10);
}

export function parts(s: DateStr): { y: number; m: number; d: number } {
  return { y: Number(s.slice(0, 4)), m: Number(s.slice(5, 7)), d: Number(s.slice(8, 10)) };
}

export function daysInMonth(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

const pad = (n: number, w = 2) => String(n).padStart(w, '0');

/** Monta uma data; o mês pode "transbordar" (13 = janeiro do ano seguinte) e o dia é limitado ao fim do mês. */
export function makeDate(y: number, m: number, d: number): DateStr {
  const total = y * 12 + (m - 1);
  const yy = Math.floor(total / 12);
  const mm = total - yy * 12 + 1;
  const dd = Math.max(1, Math.min(d, daysInMonth(yy, mm)));
  return `${pad(yy, 4)}-${pad(mm)}-${pad(dd)}`;
}

export function addDays(s: DateStr, n: number): DateStr {
  const d = toDate(s);
  d.setUTCDate(d.getUTCDate() + n);
  return fromDate(d);
}

/** Soma meses mantendo o dia (limitado ao fim do mês: 31/01 + 1 mês = 28 ou 29/02). */
export function addMonths(s: DateStr, n: number): DateStr {
  const { y, m, d } = parts(s);
  return makeDate(y, m + n, d);
}

export function startOfMonth(s: DateStr): DateStr {
  const { y, m } = parts(s);
  return makeDate(y, m, 1);
}

export function endOfMonth(s: DateStr): DateStr {
  const { y, m } = parts(s);
  return makeDate(y, m, 31);
}

/** Semana começando na segunda-feira. */
export function startOfWeek(s: DateStr): DateStr {
  const dow = toDate(s).getUTCDay(); // 0 = domingo
  return addDays(s, -((dow + 6) % 7));
}

export function endOfWeek(s: DateStr): DateStr {
  return addDays(startOfWeek(s), 6);
}

export function maxDate(a: DateStr, b: DateStr): DateStr {
  return a > b ? a : b;
}

export function minDate(a: DateStr, b: DateStr): DateStr {
  return a < b ? a : b;
}

/** "Hoje" no fuso da aplicação (padrão America/Sao_Paulo). */
export function today(timeZone = process.env.APP_TZ || 'America/Sao_Paulo'): DateStr {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const get = (type: string) => fmt.formatToParts(new Date()).find((p) => p.type === type)!.value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}
