# SewWallet: identidade visual

## Para quem é

Para alguém que **constrói as próprias ferramentas**: hospeda o servidor em casa, acessa pelo Tailscale, faz backup todo dia, gera o próprio APK. Essa pessoa:

- **controla o dinheiro com precisão**: separa realizado de previsto, quer ver as compras do cartão pela data da compra ou pela data do pagamento, concilia o OFX item por item;
- **detesta perder trabalho e espaço**: pediu filtros compactos e criar categoria sem sair da tela;
- **não quer um app de banco**: o app é dela, feito do jeito dela.

O visual "Material padrão do Google" passa a ideia de app genérico. O SewWallet precisa parecer **feito à mão, sob medida e com cuidado**.

## Conceito: Ateliê

*Sew* é **costurar**. A metáfora é a **alfaiataria**: cada lançamento é um ponto, e o mês é uma peça costurada com paciência. Alfaiataria também é **medida exata**, e isso combina com quem confere centavo por centavo.

| Ateliê | No app |
|---|---|
| Linho, algodão cru | Fundo e superfícies em tons de papel, quentes e sem branco puro |
| Tinta de caneta-tinteiro | Texto e ações principais em azul-tinta quase preto |
| Linha de cobre | Cor de destaque: hoje, seleção, botão de adicionar, pespontos |
| Pesponto (costura tracejada) | Assinatura visual: linhas tracejadas que dividem e "costuram" os cartões |
| Etiqueta de roupa | Ícones de categoria em quadrado arredondado, como etiqueta, e não em círculo |
| Livro-caixa | Valores em fonte monoespaçada, com algarismos alinhados como numa planilha |

**Personalidade:** calma, precisa, artesanal, com um pouco de humor. Nada de gradiente, sombra pesada ou ilustração genérica de dinheiro.

## Cores

### Claro: "Linho"

| Papel | Nome | Hex | Uso |
|---|---|---|---|
| Fundo | Linho | `#F4EEE3` | Fundo das telas |
| Superfície | Papel | `#FFFBF4` | Cartões, folhas, campos |
| Superfície 2 | Algodão cru | `#ECE4D5` | Blocos secundários, chips |
| Primária | Tinta | `#1F2C38` | Texto forte, botões principais, segmento selecionado |
| Destaque | Cobre | `#B8612A` | Hoje, botão +, seleção na barra, pespontos |
| Apoio | Petróleo | `#2E6A6E` | Contas, transferências |
| Receita | Musgo | `#3A7449` | Valores de entrada |
| Despesa | Tijolo | `#AE4029` | Valores de saída |
| Atenção | Mostarda | `#A8740F` | Atrasados, faturas vencidas |
| Linha fina | Giz | `#DDD2BF` | Bordas e divisórias |

### Escuro: "Feltro"

| Papel | Hex |
|---|---|
| Fundo (Feltro) | `#14181C` |
| Superfície | `#1B2025` |
| Superfície 2 | `#252B31` |
| Texto | `#EDE5D6` |
| Primária / destaque (Cobre claro) | `#E3A06A` |
| Apoio (Petróleo claro) | `#7FB7B9` |
| Receita | `#8CC69A` |
| Despesa | `#EE8D77` |
| Atenção | `#E4B75C` |
| Linha fina | `#343B42` |

**Regras:**
- Verde e vermelho só para dinheiro entrando e saindo. Cobre nunca significa valor.
- Cobre é tempero: no máximo um ou dois pontos de cobre por tela, como hoje, o botão + e o item selecionado.
- Nada de branco puro (`#FFF`) nem preto puro.

## Tipografia

| Papel | Fonte | Por quê |
|---|---|---|
| Títulos e números grandes | **Fraunces** (serifada "macia") | Tom editorial e artesanal, de etiqueta de ateliê |
| Texto e interface | **DM Sans** | Limpa e legível, sem a cara de Roboto |
| Valores (R$) | **IBM Plex Mono** | Algarismos alinhados, cara de livro-caixa e de terminal |

- Títulos de tela alinhados à esquerda, em Fraunces.
- Todo valor em dinheiro usa a fonte mono com algarismos tabulares.
- As fontes vêm do pacote `google_fonts`. O navegador as baixa uma vez e depois usa o cache. Sem internet, o app cai na fonte do sistema. Próximo passo: embutir os arquivos em `assets/fonts` para o APK funcionar 100% offline.

## Formas

- **Cantos:** 14 px nos cartões, 12 px em botões e campos, 10 px em segmentos e etiquetas, 22 px no topo das folhas (bottom sheets). Botões não são "pílula": o retângulo arredondado foge do visual padrão do Google.
- **Sombras:** nenhuma. A profundidade vem de borda fina (Giz) e da troca de tom entre Linho e Papel.
- **Pesponto:** linha tracejada (traço 6, espaço 4, 1,3 px) em cobre translúcido. Ela aparece:
  - por dentro do cartão de resumo, como um remendo costurado;
  - embaixo do cabeçalho de cada dia na lista de lançamentos;
  - no topo da barra de navegação.
- **Etiquetas:** os ícones de categoria, conta e cartão ficam em quadrado arredondado com a cor da categoria a 14%.

## Componentes

| Componente | Como fica |
|---|---|
| Barra superior | Fundo Linho, título em Fraunces alinhado à esquerda, sem sombra |
| Cartão de resumo | Papel, borda Giz e pesponto interno; saldo grande em Fraunces |
| Cabeçalho do dia | Data em Fraunces, saldos em mono, pesponto embaixo; "Hoje" em etiqueta cobre |
| Botão principal | Tinta com texto Linho (no escuro: Cobre claro com texto escuro) |
| Botão + (FAB) | Cobre, quadrado arredondado 18 px |
| Segmentos | Selecionado em Tinta, os demais com contorno Giz |
| Barra de navegação | Papel, indicador cobre translúcido em retângulo, pesponto no topo |
| Campos | Papel preenchido, borda Giz e foco em Cobre |
| Avisos (snackbar) | Tinta, flutuante, cantos 12 |

## Marca

Logotipo em texto: **sew** em Fraunces itálico + **wallet** em DM Sans, com um pesponto cobre embaixo. Ele aparece no login e nas configurações. O ícone do app (APK e favicon) ainda é o padrão e deve ser refeito depois, com um "S" costurado.

## Voz

Direta, em português do Brasil, com uma pitada de costura quando cabe, nunca no meio de uma informação importante.

| Situação | Texto |
|---|---|
| Login | "Finanças sob medida, no seu servidor." |
| Mês vazio | "Nenhum ponto dado neste mês ainda." |
| Dia vazio | "Nada por aqui hoje." |

Mensagens de erro e confirmação continuam literais e claras.

## Onde está no código

- `app/lib/theme.dart`: paleta (`SewPalette`), fontes (`SewFonts`), `ThemeData` e cores financeiras.
- `app/lib/widgets/stitch.dart`: `Stitch` (pesponto), `StitchedCard` e `SewMark` (logotipo).
- `app/lib/widgets/common.dart`: `Amount` (mono) e `IconBadge` (etiqueta).
