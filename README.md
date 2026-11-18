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
└── docker-compose.prod.yml   # PC de casa (dados reais, backup)
```

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
