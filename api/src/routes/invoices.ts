import { Router } from 'express';
import { z } from 'zod';
import { today } from '../lib/dates';
import { dateStr, id, money, notFound, parse } from '../lib/http';
import { loadLedger } from '../services/ledger';
import { payInvoice } from '../services/invoices';

export const invoicesRouter = Router();

/** Fatura com as compras e os pagamentos. */
invoicesRouter.get('/:id', async (req, res) => {
  const ledger = await loadLedger(req.userId, today());
  const invoice = ledger.invoices.find((i) => i.id === req.params.id);
  if (!invoice) throw notFound('Fatura');
  res.json({
    ...invoice,
    items: ledger.txs.filter((t) => t.invoiceId === invoice.id),
    payments: ledger.txs.filter((t) => t.paysInvoiceId === invoice.id),
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
