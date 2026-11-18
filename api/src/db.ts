import { Prisma, PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient();

/** Cliente normal ou de transação (`prisma.$transaction(async (tx) => ...)`). */
export type Db = Prisma.TransactionClient;
