import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db';
import { parse } from '../lib/http';
import { ownedCategory } from '../services/owned';

export const categoriesRouter = Router();

const categorySchema = z.object({
  name: z.string().trim().min(1).max(60),
  kind: z.enum(['INCOME', 'EXPENSE']),
  color: z.string().max(20).nullish(),
  icon: z.string().max(40).nullish(),
});

categoriesRouter.get('/', async (req, res) => {
  res.json(
    await prisma.category.findMany({ where: { userId: req.userId }, orderBy: [{ kind: 'asc' }, { name: 'asc' }] }),
  );
});

categoriesRouter.post('/', async (req, res) => {
  const body = parse(categorySchema, req.body);
  res.status(201).json(await prisma.category.create({ data: { ...body, userId: req.userId } }));
});

categoriesRouter.put('/:id', async (req, res) => {
  await ownedCategory(req.userId, req.params.id);
  // O tipo (receita/despesa) não muda: os lançamentos já vinculados ficariam inconsistentes.
  const body = parse(categorySchema.omit({ kind: true }).partial(), req.body);
  res.json(await prisma.category.update({ where: { id: req.params.id }, data: body }));
});

/** Os lançamentos da categoria ficam sem categoria. */
categoriesRouter.delete('/:id', async (req, res) => {
  await ownedCategory(req.userId, req.params.id);
  await prisma.category.delete({ where: { id: req.params.id } });
  res.status(204).end();
});
