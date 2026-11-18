import { prisma, type Db } from '../db';
import { notFound } from '../lib/http';

// Garante que o registro pertence ao usuário logado.

export async function ownedAccount(userId: string, id: string, db: Db = prisma) {
  const row = await db.account.findFirst({ where: { id, userId } });
  if (!row) throw notFound('Conta');
  return row;
}

export async function ownedCard(userId: string, id: string, db: Db = prisma) {
  const row = await db.creditCard.findFirst({ where: { id, userId } });
  if (!row) throw notFound('Cartão');
  return row;
}

export async function ownedCategory(userId: string, id: string, db: Db = prisma) {
  const row = await db.category.findFirst({ where: { id, userId } });
  if (!row) throw notFound('Categoria');
  return row;
}

export async function ownedTransaction(userId: string, id: string, db: Db = prisma) {
  const row = await db.transaction.findFirst({ where: { id, userId } });
  if (!row) throw notFound('Lançamento');
  return row;
}

export async function ownedInvoice(userId: string, id: string, db: Db = prisma) {
  const row = await db.invoice.findFirst({ where: { id, card: { userId } }, include: { card: true } });
  if (!row) throw notFound('Fatura');
  return row;
}
