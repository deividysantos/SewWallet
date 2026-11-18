import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db';
import { env } from '../env';
import { requireAuth, signToken } from '../lib/auth';
import { HttpError, parse } from '../lib/http';
import { createUser, publicUser, verifyLogin } from '../services/users';

export const authRouter = Router();

const registerSchema = z.object({
  name: z.string().trim().min(1).max(80),
  username: z.string().trim().min(3).max(40).regex(/^[a-zA-Z0-9._-]+$/, 'Use letras, números, ponto, _ ou -'),
  password: z.string().min(8).max(200),
});

const loginSchema = z.object({ username: z.string().min(1), password: z.string().min(1) });

authRouter.post('/register', async (req, res) => {
  if (!env.allowRegistration) throw new HttpError(403, 'Cadastro desabilitado');
  const body = parse(registerSchema, req.body);
  const user = await createUser(body);
  res.status(201).json({ token: signToken(user.id), user: publicUser(user) });
});

authRouter.post('/login', async (req, res) => {
  const body = parse(loginSchema, req.body);
  const user = await verifyLogin(body.username, body.password);
  if (!user) throw new HttpError(401, 'Usuário ou senha inválidos');
  res.json({ token: signToken(user.id), user: publicUser(user) });
});

authRouter.get('/me', requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.userId } });
  if (!user) throw new HttpError(401, 'Usuário não existe mais');
  res.json(publicUser(user));
});
