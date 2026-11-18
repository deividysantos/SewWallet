/**
 * Dados FICTÍCIOS para desenvolvimento. As datas são relativas a hoje, então o
 * cenário sempre tem passado (pago), hoje e futuro (pendente).
 *
 * Login de exemplo: usuário `demo`, senha `demo1234`.
 * Recriar do zero: docker compose exec api npm run db:reset
 */
import { prisma } from '../src/db';
import { addDays, makeDate, parts, startOfMonth, today as todayFn } from '../src/lib/dates';
import { payInvoice } from '../src/services/invoices';
import { loadLedger } from '../src/services/ledger';
import { createTransaction, type CreateTxInput } from '../src/services/transactions';
import { createUser } from '../src/services/users';

const DEMO_USERNAME = 'demo';
const DEMO_PASSWORD = 'demo1234';

const reais = (v: number) => Math.round(v * 100);

async function main() {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('Seed de dados fictícios não roda em produção');
  }
  if (await prisma.user.findUnique({ where: { username: DEMO_USERNAME } })) {
    console.log('[seed] Usuário demo já existe; nada a fazer.');
    return;
  }

  const T = todayFn();
  const { y, m } = parts(startOfMonth(T));
  /** Dia `day` do mês atual + `offset` meses. */
  const M = (offset: number, day: number) => makeDate(y, m + offset, day);

  const user = await createUser({ name: 'Usuário Demo', username: DEMO_USERNAME, password: DEMO_PASSWORD });
  const categories = await prisma.category.findMany({ where: { userId: user.id } });
  const cat = (name: string) => {
    const c = categories.find((x) => x.name === name);
    if (!c) throw new Error(`Categoria ${name} não existe`);
    return c.id;
  };

  const nubank = await prisma.account.create({
    data: { userId: user.id, name: 'Nubank', type: 'CHECKING', initialBalance: reais(3500), color: '#820AD1' },
  });
  const itau = await prisma.account.create({
    data: { userId: user.id, name: 'Itaú', type: 'CHECKING', initialBalance: reais(1200), color: '#EC7000' },
  });
  const carteira = await prisma.account.create({
    data: { userId: user.id, name: 'Carteira', type: 'WALLET', initialBalance: reais(150), color: '#43A047' },
  });

  const roxinho = await prisma.creditCard.create({
    data: {
      userId: user.id,
      name: 'Nubank Roxinho',
      limit: reais(8000),
      closingDay: 5,
      dueDay: 12,
      paymentAccountId: nubank.id,
      color: '#820AD1',
    },
  });
  const itauVisa = await prisma.creditCard.create({
    data: {
      userId: user.id,
      name: 'Itaú Visa',
      limit: reais(5000),
      closingDay: 25,
      dueDay: 5,
      paymentAccountId: itau.id,
      color: '#EC7000',
    },
  });

  const add = (input: CreateTxInput) => createTransaction(user.id, input, T);

  // Fixos (começam 3 meses atrás; o que já passou entra como pago).
  const fixed: CreateTxInput[] = [
    { type: 'INCOME', description: 'Salário', amount: reais(6500), date: M(-3, 5), accountId: itau.id, categoryId: cat('Salário') },
    { type: 'EXPENSE', description: 'Aluguel', amount: reais(1800), date: M(-3, 10), accountId: nubank.id, categoryId: cat('Moradia') },
    { type: 'EXPENSE', description: 'Internet', amount: reais(119.9), date: M(-3, 15), accountId: nubank.id, categoryId: cat('Contas da casa') },
    { type: 'EXPENSE', description: 'Academia', amount: reais(99.9), date: M(-3, 1), accountId: itau.id, categoryId: cat('Saúde'), recurrence: { frequency: 'MONTHLY', interval: 1, endDate: M(6, 1) } },
    { type: 'EXPENSE', description: 'Netflix', amount: reais(55.9), date: M(-3, 8), cardId: roxinho.id, categoryId: cat('Assinaturas') },
    { type: 'EXPENSE', description: 'Spotify', amount: reais(21.9), date: M(-3, 20), cardId: itauVisa.id, categoryId: cat('Assinaturas') },
    { type: 'TRANSFER', description: 'Reserva para contas', amount: reais(3500), date: M(-3, 6), accountId: itau.id, toAccountId: nubank.id },
  ];
  for (const f of fixed) {
    await add({ ...f, status: 'PAID', recurrence: f.recurrence ?? { frequency: 'MONTHLY', interval: 1 } });
  }

  // Parcelados.
  await add({ type: 'EXPENSE', description: 'Notebook', amount: reais(4800), date: M(-2, 14), cardId: roxinho.id, categoryId: cat('Compras'), installments: { total: 10, amountIs: 'total' } });
  await add({ type: 'EXPENSE', description: 'Geladeira', amount: reais(3000), date: M(-1, 22), cardId: itauVisa.id, categoryId: cat('Compras'), installments: { total: 6, amountIs: 'total' } });
  await add({ type: 'EXPENSE', description: 'Curso de inglês (boleto)', amount: reais(450), date: M(0, 18), accountId: nubank.id, categoryId: cat('Educação'), installments: { total: 3, amountIs: 'each' } });

  // Avulsos.
  const oneOffs: CreateTxInput[] = [];
  for (let offset = -3; offset <= 0; offset++) {
    oneOffs.push(
      { type: 'EXPENSE', description: 'Mercado', amount: reais(412.37 + offset * 13), date: M(offset, 3), cardId: roxinho.id, categoryId: cat('Mercado') },
      { type: 'EXPENSE', description: 'Mercado', amount: reais(287.15 - offset * 9), date: M(offset, 17), accountId: nubank.id, categoryId: cat('Mercado') },
      { type: 'EXPENSE', description: 'Restaurante', amount: reais(96.5), date: M(offset, 9), cardId: itauVisa.id, categoryId: cat('Alimentação') },
      { type: 'EXPENSE', description: 'Uber', amount: reais(34.8), date: M(offset, 12), cardId: roxinho.id, categoryId: cat('Transporte') },
      { type: 'EXPENSE', description: 'Combustível', amount: reais(220), date: M(offset, 21), cardId: itauVisa.id, categoryId: cat('Transporte') },
      { type: 'EXPENSE', description: 'Feira', amount: reais(48), date: M(offset, 23), accountId: carteira.id, categoryId: cat('Mercado') },
      { type: 'EXPENSE', description: 'Conta de luz', amount: reais(198.4 + offset * 7), date: M(offset, 7), accountId: itau.id, categoryId: cat('Contas da casa') },
    );
  }
  oneOffs.push(
    { type: 'INCOME', description: 'Freelance site', amount: reais(1800), date: M(-2, 26), accountId: nubank.id, categoryId: cat('Freelance') },
    { type: 'INCOME', description: 'Freelance app', amount: reais(2400), date: M(0, 27), accountId: nubank.id, categoryId: cat('Freelance') },
    { type: 'EXPENSE', description: 'Farmácia', amount: reais(87.9), date: addDays(T, -1), cardId: roxinho.id, categoryId: cat('Saúde') },
    { type: 'INCOME', description: 'Estorno Uber', amount: reais(12.4), date: addDays(T, -2), cardId: roxinho.id, categoryId: cat('Outras receitas') },
    { type: 'EXPENSE', description: 'IPVA', amount: reais(1250), date: M(1, 15), accountId: itau.id, categoryId: cat('Impostos e taxas') },
    { type: 'TRANSFER', description: 'Saque', amount: reais(200), date: M(-1, 2), accountId: nubank.id, toAccountId: carteira.id },
  );
  for (const o of oneOffs) await add(o);

  // Uma conta atrasada (pendente no passado) para ver o destaque e o efeito no saldo previsto.
  await add({ type: 'EXPENSE', description: 'Conta de água', amount: reais(89.6), date: addDays(T, -4), accountId: itau.id, categoryId: cat('Contas da casa'), status: 'PENDING' });

  // Paga as faturas que já venceram.
  const ledger = await loadLedger(user.id, T);
  for (const inv of ledger.invoices) {
    if (inv.dueDate < T && inv.remaining > 0) {
      await payInvoice(user.id, inv.id, { date: inv.dueDate, status: 'PAID' });
    }
  }

  const count = await prisma.transaction.count({ where: { userId: user.id } });
  console.log(`[seed] Usuário demo criado com ${count} lançamentos (hoje = ${T}).`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
