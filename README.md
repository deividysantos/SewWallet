# SewWallet

App pessoal de finanças: lançamentos a pagar/receber, contas, cartões com faturas,
parcelados, fixos e relatórios de fluxo de caixa.

## Stack

| Camada | Tecnologia |
|---|---|
| App | Flutter (web durante o desenvolvimento, APK para Android) |
| API | Node + Express + TypeScript + Prisma |
| Banco | PostgreSQL |
| Infra | Docker Compose; acesso remoto via Tailscale |

## Estrutura

```
SewWallet/
├── api/                      # API Node + Express + TypeScript + Prisma
├── app/                      # App Flutter
├── docker/                   # Dockerfiles
├── docker-compose.yml        # Desenvolvimento (dados de exemplo)
└── docker-compose.prod.yml   # PC de casa (dados reais, backup) — ainda não criado
```

## Rodando em desenvolvimento

Só precisa do Docker.

```bash
docker compose up -d --build      # sobe Postgres + API (com dados de exemplo)
docker compose logs -f api        # acompanha a API
docker compose exec api npm test  # testes das regras (faturas, saldos, fluxo de caixa)
docker compose exec api npm run db:reset   # apaga tudo e recria os dados de exemplo
```

- API: http://localhost:3000 (Postgres exposto em `localhost:5433` para ferramentas de banco)
- Login de exemplo: veja o topo de [api/prisma/seed.ts](api/prisma/seed.ts).
  Os dados são fictícios e as datas são relativas a hoje.
- Mudou o `schema.prisma`? `docker compose exec api npx prisma migrate dev --name <nome>`.

## API

Valores em **centavos** (inteiros) e datas em `AAAA-MM-DD`. Tudo exige
`Authorization: Bearer <token>`, exceto `/health` e `/auth/*`.

| Rota | O que faz |
|---|---|
| `POST /auth/register`, `POST /auth/login`, `GET /auth/me` | Cadastro (se `ALLOW_REGISTRATION=true`), login e usuário logado |
| `GET/POST/PUT/DELETE /accounts` | Contas, com `balance` (saldo atual) e `projectedMonthEnd` |
| `GET/POST/PUT/DELETE /categories` | Categorias (padrões criadas no cadastro) |
| `GET/POST/PUT/DELETE /cards`, `GET /cards/:id/invoices` | Cartões com fatura atual e limite usado; faturas do cartão |
| `GET /invoices/:id`, `POST /invoices/:id/payments` | Fatura com compras e pagamentos; pagar total ou parcial |
| `GET /transactions` | Lançamentos agrupados por dia com saldo `realized`/`projected` no fim de cada dia. Filtros: `from`, `to`, `accountIds`, `cardIds`, `categoryIds`, `type`, `status`, `search`, `includeCards` |
| `POST /transactions` | Lançamento simples, parcelado (`installments`) ou fixo (`recurrence`) |
| `PUT /transactions/:id?scope=one\|future\|all`, `DELETE ...?scope=` | Editar/excluir este, este e os próximos, ou todos (fixos e parcelados) |
| `PATCH /transactions/:id/status` | Marcar como pago/pendente |
| `GET /reports/cashflow` | Fluxo de caixa: `granularity=day\|week\|month`, `mode=period\|cumulative`, `basis=projected\|realized`, `from`, `to`, `accountIds` |

## Ambientes

- **Desenvolvimento**: qualquer PC com Docker. Banco com dados fictícios, descartável.
- **Produção**: PC de casa. Dados reais, backup automático, acesso pelo celular via Tailscale.

## Regras de negócio (decisões)

- Finanças separadas por usuário (login com usuário e senha).
- Lançamentos: receita, despesa ou transferência; status pendente ou pago.
- Saldo diário na tela de lançamentos: **realizado** (só pagos) e **previsto** (pagos + pendentes).
- Cartão: a compra entra na fatura conforme o dia de fechamento (configurável se o próprio
  dia conta na fatura atual ou na próxima). A fatura afeta o saldo da conta na data de vencimento.
- Pendentes atrasados ficam na data original, destacados; no saldo previsto contam como se
  fossem pagos hoje.
- Parcelados geram uma parcela real por mês, cada uma na fatura correta.
- Fixos sem data final são projetados para os próximos 12 meses.
- Fluxo de caixa com filtro de período começa do zero; sem filtro, saldo acumulado desde o
  início. Visões por dia, semana e mês.
