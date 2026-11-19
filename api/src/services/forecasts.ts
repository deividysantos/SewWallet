import { z } from 'zod';
import { prisma, type Db } from '../db';
import { maxDate, toDate, type DateStr } from '../lib/dates';
import { HttpError } from '../lib/http';
import { ownedTransaction } from './owned';
import { ensureRecurrences, horizon } from './recurrence';

/** Query `forecasts=true|false` (padrão true): considerar previsões abertas. */
export const forecastsParam = z
  .enum(['true', 'false'])
  .default('true')
  .transform((v) => v === 'true');

/** Antes de ler o ledger: gera os fixos até `until` e expira previsões vencidas. */
export async function refreshLedger(userId: string, today: DateStr, until: DateStr): Promise<void> {
  await ensureRecurrences(userId, maxDate(horizon(today), until));
  await expireForecasts(userId, today);
}

/** Previsões abertas cuja data já passou viram EXPIRED (saem dos saldos, ficam no histórico). */
export async function expireForecasts(userId: string, today: DateStr): Promise<number> {
  const { count } = await prisma.transaction.updateMany({
    where: { userId, isForecast: true, forecastState: 'OPEN', date: { lt: toDate(today) } },
    data: { forecastState: 'EXPIRED' },
  });
  return count;
}

/** Encerra (OK) ou reabre uma previsão. Só reabre se a data ainda não passou. */
export async function setForecastState(userId: string, txId: string, state: 'OPEN' | 'CLOSED', today: DateStr) {
  const current = await ownedTransaction(userId, txId);
  if (!current.isForecast) throw new HttpError(400, 'Lançamento não é uma previsão');
  if (state === 'OPEN' && current.date < toDate(today)) {
    throw new HttpError(400, 'A data da previsão já passou; mude a data para reabrir');
  }
  return prisma.transaction.update({ where: { id: txId }, data: { forecastState: state } });
}

/** Valida a previsão que um lançamento real vai abater. */
export async function checkForecastLink(
  userId: string,
  forecastId: string,
  type: string,
  db: Db = prisma,
): Promise<void> {
  const f = await db.transaction.findFirst({ where: { id: forecastId, userId } });
  if (!f || !f.isForecast) throw new HttpError(400, 'Previsão não encontrada');
  if (f.forecastState !== 'OPEN') throw new HttpError(400, 'Essa previsão não está aberta');
  if (f.type !== type) throw new HttpError(400, 'A previsão é de outro tipo');
}
