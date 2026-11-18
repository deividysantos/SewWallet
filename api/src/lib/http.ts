import { z, type ZodTypeAny } from 'zod';
import { isDateStr } from './dates';

export class HttpError extends Error {
  constructor(
    public status: number,
    message: string,
    public details?: unknown,
  ) {
    super(message);
  }
}

export const notFound = (what: string) => new HttpError(404, `${what} não encontrado(a)`);

export function parse<S extends ZodTypeAny>(schema: S, data: unknown): z.infer<S> {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw new HttpError(400, 'Dados inválidos', result.error.flatten());
  }
  return result.data;
}

export const dateStr = z.string().refine(isDateStr, 'Data inválida (use AAAA-MM-DD)');
/** Valor em centavos, positivo. */
export const money = z.number().int().positive().max(2_000_000_000);
export const id = z.string().min(1).max(64);
/** Lista separada por vírgula em query string. */
export const idList = z
  .string()
  .optional()
  .transform((v) => (v ? v.split(',').map((s) => s.trim()).filter(Boolean) : undefined));
