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
├── docker-compose.prod.yml   # PC de casa (dados reais, backup)
└── .env.prod.example         # Modelo do .env.prod (segredos da produção, fora do Git)
```

## Rodando em desenvolvimento

Só precisa do Docker.

```bash
docker compose up -d --build      # sobe Postgres + API (com dados de exemplo)
docker compose logs -f api        # acompanha a API
docker compose exec api npm test  # testes das regras (faturas, saldos, fluxo de caixa)
docker compose exec api npm run db:reset   # apaga tudo e recria os dados de exemplo
```

- **App (web): http://localhost:8080.** Recompila sozinho quando você salva algo em `app/`
  (leva ~2 min); depois é só recarregar a página. Acompanhe com `docker compose logs -f web`.
- API: http://localhost:3000 (Postgres exposto em `localhost:5433` para ferramentas de banco)
- Login de exemplo: veja o topo de [api/prisma/seed.ts](api/prisma/seed.ts).
  Os dados são fictícios e as datas são relativas a hoje.
- Mudou o `schema.prisma`? `docker compose exec api npx prisma migrate dev --name <nome>`.

## Rodando em produção (PC de casa)

Roda ao lado do dev, com projeto, volumes e portas próprios.

```bash
cp .env.prod.example .env.prod    # troque senha, JWT_SECRET e PUBLIC_API_URL (IP do Tailscale)
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
docker compose -f docker-compose.prod.yml --env-file .env.prod logs -f api
```

| | Dev | Produção |
|---|---|---|
| App web | http://localhost:8080 | http://localhost:8081 (celular: `http://<ip-tailscale>:8081`) |
| API | http://localhost:3000 | http://localhost:3001 (celular: `http://<ip-tailscale>:3001`) |
| Postgres | `localhost:5433` | `127.0.0.1:5434` (só no próprio PC) |
| Dados | fictícios (seed) | reais, sem seed |

- **Primeiro uso**: com `ALLOW_REGISTRATION=true`, crie seu usuário pelo app; depois mude para
  `false` no `.env.prod` e rode o `up -d` de novo.
- **Backup**: o serviço `backup` faz `pg_dump` ao subir e todo dia às `BACKUP_HOUR` em `backups/`,
  mantendo `BACKUP_KEEP_DAYS` dias. Restaurar:
  `gunzip -c backups/<arquivo>.sql.gz | docker compose -f docker-compose.prod.yml --env-file .env.prod exec -T db psql -U sewwallet -d sewwallet`
- Mudou o código? Rode o `up -d --build` de novo (a produção não recompila sozinha).
- Os containers têm `restart: unless-stopped`: voltam sozinhos se o Docker Desktop iniciar com o Windows.

## Gerando o APK (Android)

O SDK do Android já vem no container do Flutter; não precisa instalar nada no Windows.

```bash
docker compose --env-file .env.prod --profile tools run --rm apk
```

- Sai em `releases/sewwallet-<versão>.apk` (fora do Git). A API padrão é o `PUBLIC_API_URL`
  do `.env.prod`; dá para trocar o servidor na tela de login.
- O celular precisa estar com o Tailscale ligado para falar com a API.
- Assinado com a chave de debug por enquanto: instale permitindo "fontes desconhecidas".
- Para lançar uma versão nova, aumente `version:` em `app/pubspec.yaml` (ex.: `1.0.0+2`).

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
| `GET /transactions` | Lançamentos agrupados por dia com saldo `realized`/`projected` no fim de cada dia. Filtros: `from`, `to`, `accountIds`, `cardIds`, `categoryIds`, `type`, `status`, `search`, `includeCards`, `forecasts=true\|false` |
| `POST /transactions` | Lançamento simples, parcelado (`installments`) ou fixo (`recurrence`); previsão com `isForecast: true`; lançamento real que abate uma previsão com `forecastId`; `counterpart: true` gera a contrapartida |
| `PUT /transactions/:id?scope=one\|future\|all`, `DELETE ...?scope=` | Editar/excluir este, este e os próximos, ou todos (fixos e parcelados). No `PUT`, `counterpart: true\|false` gera ou remove a contrapartida |
| `PATCH /transactions/:id/status` | Marcar como pago/pendente (não vale para previsões) |
| `GET /transactions/forecasts/open?type=` | Previsões abertas (para escolher qual um lançamento abate) |
| `PATCH /transactions/:id/forecast-state` | Encerrar (`CLOSED`) ou reabrir (`OPEN`) uma previsão |
| `GET /reports/cashflow` | Fluxo de caixa: `granularity=day\|week\|month`, `mode=period\|cumulative`, `basis=projected\|realized`, `from`, `to`, `accountIds`, `forecasts` |
| `GET /reports/categories`, `GET /reports/categories/detail` | Por categoria: `kind`, `basis`, `cardDate`, `from`, `to`, `forecasts` |
| `GET /reports/dashboard` | Painel do mês (`month`): saldos, receitas/despesas previsto × realizado, maiores categorias, faturas e limites, previsões e contrapartidas. Filtros: `accountIds`, `forecasts`, `counterparts` (false tira os pares origem + contrapartida dos totais) |
| `GET /reports/counterparts` | Contrapartidas do mês (pela data da contrapartida), com a origem de cada uma e totais pendente × quitado. Filtros: `accountIds` (conta da contrapartida), `cardIds` (cartão da origem), `type`, `status=PENDING\|PAID\|all` |
| `POST /suggestions/notifications` | O celular envia uma notificação de banco (`app`, `appName`, `title`, `text`, `postedAt`, `key`); a IA interpreta e a API dá baixa, ignora ou cria sugestão |
| `GET /suggestions?view=pending\|processed`, `GET /suggestions/count` | Sugestões esperando decisão (e erros da IA) / o que foi processado nos últimos 30 dias |
| `POST /suggestions/:id/accept\|dismiss\|undo\|retry` | Aceitar (com `transactionId` criado), descartar, desfazer (volta a baixa para pendente) ou reprocessar |
| `GET /report-filters`, `PUT/DELETE /report-filters/:report` | Filtro preferido de cada relatório (`dashboard`, `cashflow`, `categories`, `forecasts`, `counterparts`), sem o período |
| `GET /reports/forecasts` | Previsões do mês (`month`), com previsto/abatido/restante, fixas × avulsas e abatimentos. Filtros: `accountIds`, `cardIds`, `type`, `state=OPEN\|CLOSED\|EXPIRED\|all` |

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
- **Previsões** (a pagar / a receber): valores estimados até uma data (ex.: R$ 100 de gasolina
  até o dia 10). Podem ser avulsas ou fixas, em conta ou no cartão; não podem ser parceladas.
  - Lançamentos reais vinculados **abatem** a previsão; ela conta pelo que ainda falta abater.
  - Encerrada pelo usuário ("OK") ou **expirada** (a data passou), deixa de contar, mas fica no histórico.
  - Aparecem na lista de lançamentos em qualquer visão do cartão (também quando as compras estão
    agrupadas na fatura) e no detalhe da fatura, separadas das compras.
  - Entram no previsto da lista e dos relatórios com "Considerar previsões" (padrão nas
    Configurações, começa marcado). Nunca entram no realizado, no saldo das contas, no total da
    fatura, no valor a pagar nem no limite do cartão.
- **Contrapartida** (ex.: compra no cartão para um amigo que paga depois): lançamento de tipo
  oposto e mesmo valor, com a descrição "Compensação de: <descrição da origem>", que zera o de origem.
  - Origem no cartão: entra na conta que paga a fatura, na data de vencimento da fatura.
    Origem em conta: mesma conta e mesma data.
  - Os dois ficam ligados. O valor muda nos dois. A data também, exceto quando a origem é no
    cartão: aí a contrapartida segue o vencimento da fatura. Excluir um exclui o outro.
  - Parcelados e fixos: cada parcela/ocorrência tem a sua contrapartida.
  - Não vale para transferências, previsões e pagamentos de fatura.
- **Início**: painel do mês com saldos, resultado, faturas, limites, maiores gastos, previsões e
  contrapartidas. Filtros de contas, previsões e contrapartidas; sem período (o mês anda com ‹ ›).
- **Filtro preferido** (★ no topo do Início e de cada relatório): um por tela, salvo no servidor
  (vale no celular e na web) e aplicado ao abrir. O período não entra. Gerenciar em
  Configurações → Filtros salvos.
- **Novo lançamento**: o "+" abre os atalhos Despesa, Receita, Transferência e Cartão; o tipo e o
  cartão vêm do atalho (o formulário não tem mais a escolha Conta/Cartão). No cartão, só compra:
  estornos entram pela importação OFX.
- **Notificações dos bancos** (só no app Android; Configurações → Notificações dos bancos):
  - O serviço nativo (`BankNotificationService.kt`) lê as notificações dos apps marcados que falam
    de valor (R$) e envia para a API, mesmo com o app fechado. Sem conexão, guarda numa fila.
    Precisa liberar "Acesso a notificações" (em APK fora da loja, antes "Permitir configurações
    restritas" nas informações do app) e, de preferência, tirar o app da economia de bateria.
  - A IA (`AI_API_KEY`, `AI_BASE_URL`, `AI_MODEL` no `.env.prod`; padrão DeepSeek `deepseek-flash`,
    qualquer API no formato da OpenAI serve) extrai tipo, valor, data, conta/cartão (pelo final do
    cartão, cadastrado no cartão) e categoria (aprendendo com os lançamentos recentes).
  - Mesmo tipo e valor exato: pendente em conta no mesmo dia (ou até 10 dias de distância) recebe
    baixa; já pago, ou compra igual no cartão (±1 dia), é ignorado; senão vira **sugestão** (Início →
    ✨). Dois candidatos igualmente perto não são escolhidos sozinhos. Tudo pode ser desfeito na aba
    Processadas. O texto das notificações dos apps marcados vai para o serviço de IA.
