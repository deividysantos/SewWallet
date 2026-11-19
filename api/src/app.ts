import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import { Prisma } from '@prisma/client';
import { requireAuth } from './lib/auth';
import { HttpError } from './lib/http';
import { accountsRouter } from './routes/accounts';
import { authRouter } from './routes/auth';
import { cardsRouter } from './routes/cards';
import { categoriesRouter } from './routes/categories';
import { invoicesRouter } from './routes/invoices';
import { reportFiltersRouter } from './routes/reportFilters';
import { reportsRouter } from './routes/reports';
import { suggestionsRouter } from './routes/suggestions';
import { transactionsRouter } from './routes/transactions';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));

  app.get('/health', (_req, res) => {
    res.json({ ok: true });
  });

  app.use('/auth', authRouter);
  app.use('/accounts', requireAuth, accountsRouter);
  app.use('/categories', requireAuth, categoriesRouter);
  app.use('/cards', requireAuth, cardsRouter);
  app.use('/invoices', requireAuth, invoicesRouter);
  app.use('/transactions', requireAuth, transactionsRouter);
  app.use('/reports', requireAuth, reportsRouter);
  app.use('/report-filters', requireAuth, reportFiltersRouter);
  app.use('/suggestions', requireAuth, suggestionsRouter);

  app.use((_req, res) => {
    res.status(404).json({ error: 'Rota não encontrada' });
  });

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof HttpError) {
      res.status(err.status).json({ error: err.message, details: err.details });
      return;
    }
    if (err instanceof Prisma.PrismaClientKnownRequestError) {
      if (err.code === 'P2003') {
        res.status(409).json({ error: 'Registro em uso (ex.: conta usada para pagar um cartão)' });
        return;
      }
      if (err.code === 'P2025') {
        res.status(404).json({ error: 'Registro não encontrado' });
        return;
      }
      if (err.code === 'P2002') {
        res.status(409).json({ error: 'Registro duplicado' });
        return;
      }
    }
    if (typeof err === 'object' && err && 'type' in err && err.type === 'entity.parse.failed') {
      res.status(400).json({ error: 'JSON inválido' });
      return;
    }
    console.error(err);
    res.status(500).json({ error: 'Erro interno' });
  });

  return app;
}
