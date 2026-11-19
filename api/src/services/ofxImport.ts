import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { prisma } from '../db';
import { invoicePeriodForRef } from '../domain/invoice';
import { matchEntries, parseOfx, type OfxEntry, type OfxStatement } from '../domain/ofx';
import { addMonths, fromDate, startOfMonth, toDate, type DateStr } from '../lib/dates';
import { HttpError, id } from '../lib/http';
import { getOrCreateInvoice } from './invoices';
import { ownedCard } from './owned';

function parseFile(ofx: string): OfxStatement {
  try {
    const stmt = parseOfx(ofx);
    if (stmt.entries.length === 0) throw new Error('Nenhum lançamento encontrado no arquivo');
    return stmt;
  } catch (e) {
    throw new HttpError(400, e instanceof Error ? e.message : 'Arquivo OFX inválido');
  }
}

/** Cartão, fatura alvo (se já existir) e os itens dela, conciliados com o arquivo. */
async function load(userId: string, cardId: string, refMonth: DateStr, ofx: string) {
  const card = await ownedCard(userId, cardId);
  const ref = startOfMonth(refMonth);
  const period = invoicePeriodForRef(ref, card);
  const invoice = await prisma.invoice.findUnique({ where: { cardId_refMonth: { cardId, refMonth: toDate(ref) } } });
  const rows = invoice
    ? await prisma.transaction.findMany({
        where: { invoiceId: invoice.id, isForecast: false },
        orderBy: [{ date: 'asc' }, { createdAt: 'asc' }],
        include: { category: { select: { id: true, name: true, color: true, icon: true } } },
      })
    : [];
  const existing = rows.map((t) => ({ ...t, date: fromDate(t.date) }));
  const stmt = parseFile(ofx);
  const matches = matchEntries(stmt.entries, existing);
  return { card, ref, period, invoice, existing, stmt, matches };
}

/** Categoria usada da última vez para o mesmo nome do arquivo (ou mesma descrição). */
async function suggestCategories(userId: string, entries: OfxEntry[]) {
  const memos = [...new Set(entries.map((e) => e.memo))];
  const names = [...new Set(entries.map((e) => e.name))];
  const rows = await prisma.transaction.findMany({
    where: {
      userId,
      categoryId: { not: null },
      isForecast: false,
      OR: [{ externalName: { in: memos } }, { externalName: { in: names } }, { description: { in: names } }],
    },
    orderBy: { date: 'desc' },
    select: { type: true, categoryId: true, externalName: true, description: true },
  });
  return (e: OfxEntry): string | null => {
    const hit =
      rows.find((r) => r.type === e.type && (r.externalName === e.memo || r.externalName === e.name)) ??
      rows.find((r) => r.type === e.type && r.description === e.name);
    return hit?.categoryId ?? null;
  };
}

export async function previewOfxImport(userId: string, cardId: string, refMonth: DateStr, ofx: string) {
  const { ref, period, invoice, existing, stmt, matches } = await load(userId, cardId, refMonth, ofx);
  const suggest = await suggestCategories(userId, stmt.entries);
  const matchedIds = new Set([...matches.values()].map((m) => m.item.id));

  return {
    invoice: { id: invoice?.id ?? null, ...period, refMonth: ref },
    statement: { start: stmt.start, end: stmt.end },
    entries: stmt.entries.map((e) => {
      const m = matches.get(e.index);
      return {
        ...e,
        status: e.isPayment ? 'ignored' : m ? 'matched' : 'new',
        match: m
          ? {
              id: m.item.id,
              description: m.item.description,
              date: m.item.date,
              category: m.item.category,
              reason: m.reason,
            }
          : null,
        suggestedCategoryId: m ? null : suggest(e),
        /** Quantos lançamentos a importação cria (parcela atual + as que faltam). */
        creates: e.isPayment || m ? 0 : e.installment ? e.installment.total - e.installment.number + 1 : 1,
      };
    }),
    /** Itens da fatura no app que não estão no arquivo. */
    notInFile: existing
      .filter((x) => !matchedIds.has(x.id))
      .map((x) => ({
        id: x.id,
        description: x.description,
        amount: x.amount,
        date: x.date,
        type: x.type,
        installmentNumber: x.installmentNumber,
        installmentTotal: x.installmentTotal,
      })),
  };
}

export const importSchema = z.object({
  ofx: z.string().min(1).max(900_000),
  /** Decisões do usuário para os lançamentos novos. Os que não vierem aqui (ou com skip) não são criados. */
  items: z
    .array(
      z.object({
        index: z.number().int().min(0),
        description: z.string().trim().min(1).max(200),
        categoryId: id.nullish(),
        skip: z.boolean().optional(),
      }),
    )
    .max(2000),
});
export type ImportInput = z.infer<typeof importSchema>;

/**
 * Importa o arquivo para a fatura: grava o id/nome do arquivo nos lançamentos conciliados
 * e cria os novos (parcela k/N cria k..N, uma em cada fatura a partir desta).
 */
export async function importOfx(userId: string, cardId: string, refMonth: DateStr, input: ImportInput) {
  const { card, ref, invoice, stmt, matches } = await load(userId, cardId, refMonth, input.ofx);
  const decisions = new Map(input.items.map((i) => [i.index, i]));

  const categoryIds = [...new Set(input.items.map((i) => i.categoryId).filter((c): c is string => !!c))];
  const categories = await prisma.category.findMany({ where: { userId, id: { in: categoryIds } } });
  const kindOf = new Map(categories.map((c) => [c.id, c.kind]));

  const toCreate: { entry: OfxEntry; description: string; categoryId: string | null }[] = [];
  for (const e of stmt.entries) {
    if (e.isPayment || matches.has(e.index)) continue;
    const d = decisions.get(e.index);
    if (!d || d.skip) continue;
    const categoryId = d.categoryId ?? null;
    if (categoryId) {
      const kind = kindOf.get(categoryId);
      if (!kind) throw new HttpError(404, 'Categoria não encontrada(o)');
      if (kind !== e.type) throw new HttpError(400, `Categoria não combina com "${d.description}"`);
    }
    toCreate.push({ entry: e, description: d.description, categoryId });
  }

  return prisma.$transaction(async (tx) => {
    let linked = 0;
    for (const [index, m] of matches) {
      const e = stmt.entries[index];
      if (m.item.externalId === e.fitId && m.item.externalName === e.memo) continue;
      await tx.transaction.update({ where: { id: m.item.id }, data: { externalId: e.fitId, externalName: e.memo } });
      linked++;
    }

    const invoiceIds = new Map<number, string>();
    const invoiceAt = async (offset: number) => {
      if (!invoiceIds.has(offset)) {
        const inv = await getOrCreateInvoice(tx, card.id, invoicePeriodForRef(addMonths(ref, offset), card));
        invoiceIds.set(offset, inv.id);
      }
      return invoiceIds.get(offset)!;
    };

    let created = 0;
    for (const { entry: e, description, categoryId } of toCreate) {
      const common = {
        userId,
        type: e.type,
        status: 'PAID' as const,
        description,
        amount: e.amount,
        categoryId,
        cardId: card.id,
        externalId: e.fitId,
        externalName: e.memo,
      };
      if (!e.installment) {
        await tx.transaction.create({ data: { ...common, date: toDate(e.date), invoiceId: await invoiceAt(0) } });
        created++;
        continue;
      }
      const groupId = randomUUID();
      for (let n = e.installment.number, i = 0; n <= e.installment.total; n++, i++) {
        await tx.transaction.create({
          data: {
            ...common,
            date: toDate(addMonths(e.date, i)),
            invoiceId: await invoiceAt(i),
            installmentGroupId: groupId,
            installmentNumber: n,
            installmentTotal: e.installment.total,
          },
        });
        created++;
      }
    }

    return { created, linked, invoiceId: invoiceIds.get(0) ?? invoice?.id ?? null };
  });
}
