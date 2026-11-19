import { Router } from 'express';
import { z } from 'zod';
import { forecastEffective } from '../domain/forecast';
import { today } from '../lib/dates';
import { expireForecasts } from '../services/forecasts';
import { makeDto } from './transactions';
import { dateStr, id, money, notFound, parse } from '../lib/http';
import { loadLedger } from '../services/ledger';
import { payInvoice } from '../services/invoices';

export const invoicesRouter = Router();

/**
 * Fatura com as compras, os pagamentos e as previsões no cartão que caem nela
 * (abertas, pelo valor que falta; não entram no total nem no valor a pagar).
 */
invoicesRouter.get('/:id', async (req, res) => {
  const t = today();
  await expireForecasts(req.userId, t);
  const ledger = await loadLedger(req.userId, t);
  const invoice = ledger.invoices.find((i) => i.id === req.params.id);
  if (!invoice) throw notFound('Fatura');
  const dto = makeDto(ledger);
  res.json({
    ...invoice,
    items: ledger.txs.filter((x) => x.invoiceId === invoice.id),
    payments: ledger.txs.filter((x) => x.paysInvoiceId === invoice.id),
    forecasts: ledger.forecasts
      .filter((f) => f.invoiceId === invoice.id && forecastEffective({ ...f, amount: f.forecastPlanned }, t) > 0)
      .map((f) => dto.tx(f)),
  });
});

const paySchema = z.object({
  accountId: id.optional(),
  /** Centavos; padrão = valor restante (pagamento total). */
  amount: money.optional(),
  date: dateStr.optional(),
  status: z.enum(['PENDING', 'PAID']).optional(),
});

invoicesRouter.post('/:id/payments', async (req, res) => {
  const body = parse(paySchema, req.body ?? {});
  res.status(201).json(await payInvoice(req.userId, req.params.id, body));
});
