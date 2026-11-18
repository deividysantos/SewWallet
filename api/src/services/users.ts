import bcrypt from 'bcryptjs';
import type { CategoryKind, User } from '@prisma/client';
import { prisma } from '../db';
import { HttpError } from '../lib/http';

const DEFAULT_CATEGORIES: { name: string; kind: CategoryKind; color: string; icon: string }[] = [
  { name: 'Salário', kind: 'INCOME', color: '#2E7D32', icon: 'payments' },
  { name: 'Freelance', kind: 'INCOME', color: '#00897B', icon: 'work' },
  { name: 'Investimentos', kind: 'INCOME', color: '#1565C0', icon: 'trending_up' },
  { name: 'Outras receitas', kind: 'INCOME', color: '#558B2F', icon: 'add_circle' },
  { name: 'Alimentação', kind: 'EXPENSE', color: '#EF6C00', icon: 'restaurant' },
  { name: 'Mercado', kind: 'EXPENSE', color: '#F9A825', icon: 'shopping_cart' },
  { name: 'Moradia', kind: 'EXPENSE', color: '#6D4C41', icon: 'home' },
  { name: 'Contas da casa', kind: 'EXPENSE', color: '#5E35B1', icon: 'bolt' },
  { name: 'Transporte', kind: 'EXPENSE', color: '#3949AB', icon: 'directions_car' },
  { name: 'Saúde', kind: 'EXPENSE', color: '#D81B60', icon: 'favorite' },
  { name: 'Educação', kind: 'EXPENSE', color: '#00838F', icon: 'school' },
  { name: 'Lazer', kind: 'EXPENSE', color: '#8E24AA', icon: 'celebration' },
  { name: 'Assinaturas', kind: 'EXPENSE', color: '#C62828', icon: 'subscriptions' },
  { name: 'Compras', kind: 'EXPENSE', color: '#AD1457', icon: 'shopping_bag' },
  { name: 'Impostos e taxas', kind: 'EXPENSE', color: '#455A64', icon: 'receipt_long' },
  { name: 'Outras despesas', kind: 'EXPENSE', color: '#757575', icon: 'more_horiz' },
];

export const normalizeUsername = (u: string) => u.trim().toLowerCase();

export async function createUser(input: { name: string; username: string; password: string }): Promise<User> {
  const username = normalizeUsername(input.username);
  if (await prisma.user.findUnique({ where: { username } })) {
    throw new HttpError(409, 'Usuário já existe');
  }
  const passwordHash = await bcrypt.hash(input.password, 10);
  return prisma.user.create({
    data: {
      name: input.name.trim(),
      username,
      passwordHash,
      categories: { create: DEFAULT_CATEGORIES },
    },
  });
}

export async function verifyLogin(username: string, password: string): Promise<User | null> {
  const user = await prisma.user.findUnique({ where: { username: normalizeUsername(username) } });
  if (!user) return null;
  return (await bcrypt.compare(password, user.passwordHash)) ? user : null;
}

export const publicUser = (u: User) => ({ id: u.id, name: u.name, username: u.username });
