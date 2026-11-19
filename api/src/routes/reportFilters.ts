import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db';
import { parse } from '../lib/http';

/** Filtro preferido de cada relatório (um por relatório e usuário). */
export const reportFiltersRouter = Router();

const reportKey = z.enum(['cashflow', 'categories', 'forecasts', 'counterparts', 'dashboard']);
const paramsSchema = z
  .record(z.string(), z.unknown())
  .refine((v) => JSON.stringify(v).length <= 4000, 'Filtro grande demais');

const dto = (f: { report: string; params: unknown; updatedAt: Date }) => ({
  report: f.report,
  params: f.params,
  updatedAt: f.updatedAt.toISOString(),
});

reportFiltersRouter.get('/', async (req, res) => {
  const rows = await prisma.reportFilter.findMany({ where: { userId: req.userId }, orderBy: { report: 'asc' } });
  res.json(rows.map(dto));
});

/** Salva (ou troca) o filtro preferido do relatório. */
reportFiltersRouter.put('/:report', async (req, res) => {
  const report = parse(reportKey, req.params.report);
  const { params } = parse(z.object({ params: paramsSchema }), req.body);
  const row = await prisma.reportFilter.upsert({
    where: { userId_report: { userId: req.userId, report } },
    create: { userId: req.userId, report, params: params as object },
    update: { params: params as object },
  });
  res.json(dto(row));
});

reportFiltersRouter.delete('/:report', async (req, res) => {
  const report = parse(reportKey, req.params.report);
  await prisma.reportFilter.deleteMany({ where: { userId: req.userId, report } });
  res.status(204).end();
});
