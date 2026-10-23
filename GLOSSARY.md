# Glossário

Termos de domínio e de arquitetura do Tracker. Domínio por bounded context:
os `CONTEXT.md`/`README.md` de `app/domains/*/` têm o detalhe de cada um; aqui
ficam os termos que atravessam mais de um domínio.

## Domínio

- **To-Do (Tarefa)** — unidade de pendência, com origem e estado. Ver
  `app/domains/todos/CONTEXT.md`.
- **Fila de atenção** — o board de To-Dos agrupado por Status; pendências
  ordenadas pelo que vence primeiro.
- **Entrega** — o que conta como trabalho feito no dia: card movido por mim,
  PR mergeado, review dada. A regra vive em `Tracking::UseCases::BuildDayReport`.
- **Card** (`Tracking::Entities::Card`) — um card do Jira já normalizado. O
  adapter resolve `mine`; o domínio não compara account ids. Ver
  `app/domains/tracking/README.md`.
- **Atividade** (`Tracking::Entities::Activity`) — uma entrada de changelog ou
  um comentário de um card do Jira, já normalizada (é minha?, instante, itens
  de status). É o que o adapter entrega ao domínio; o detalhe de transporte
  (epoch ms, formato de author, accountId) não passa daqui.
- **Relatório do dia** (`Tracking::Entities::DayReport`) — o dia agregado e
  ordenado, pronto para render: itens, reviews dadas, commits, épico comum.
- **Seção do dia** (`Tracking::Notion::Section`) — o trecho de uma page que
  pertence a um dia: header (`heading_2` com a data), sentinel e body. No Brag
  é reconstruída; no 1-on-1 só se appenda.
- **Sentinel** — parágrafo que marca "daqui para baixo é gerado pelo Tracker".
  É a convenção de posse que sobrevive à perda do ledger.
- **Ledger** (`Tracker::Brag::BlockLedger`) — registro local dos ids que o
  Tracker criou no Brag, com assinatura do conteúdo. Não é estado de domínio
  ([ADR 0002](docs/adr/0002-ledger-local-do-brag.md)).

## Arquitetura

Vocabulário de *deep modules* usado nas decisões deste repo.

- **Módulo** — qualquer coisa com interface e implementação (função, classe,
  pacote, fatia entre camadas).
- **Interface** — tudo o que o chamador precisa saber para usar o módulo
  corretamente: assinatura, invariantes, ordem, modos de erro, configuração.
- **Implementação** — o corpo do módulo. Distinto de **adapter**, que descreve
  papel (o que preenche o seam), não substância.
- **Profundidade** — alavancagem na interface: quanto comportamento o chamador
  (ou o teste) exercita por unidade de interface que precisa aprender. Módulo
  **profundo** = muita implementação atrás de interface pequena; **raso** =
  interface quase do tamanho da implementação.
- **Seam** — lugar onde se altera comportamento sem editar ali; é onde a
  interface de um módulo vive.
- **Adapter** — o que satisfaz uma interface num seam. Um adapter = seam
  hipotético; dois = seam real.
- **Alavancagem** — o que o chamador ganha com profundidade: mais capacidade
  por unidade de interface. Uma implementação paga em N chamadores e M testes.
- **Localidade** — o que o mantenedor ganha: mudança, bug e verificação se
  concentram num lugar em vez de se espalhar pelos chamadores.

### Interfaces do repo

- `Tracker::HTTP.call(method:, url:, headers:, body:, query:, error:)` — política
  de transporte (timeouts, 429, erro) para Notion/Jira/GitHub.
- `Tracker::Notion::PageDays#section(day)` / `#sections` — leitura de page com
  registros por dia (Brag e 1-on-1). Devolve `Tracker::Notion::Section`
  (`day`, `header_id`, `body`, `body_ids`, `last_id`), não blocos crus: quem
  pergunta "qual é a seção do dia" não recombina predicados. `.day_of(block)`,
  `.text_of(block)` e `.marker(day)` são funções de módulo (não dependem da
  page). Só leitura: posse de escrita continua com cada repositório.
- `Tracking::BragDocument#rewrite(day, report)` / `#adopt(day)` / `#forget(days)`
  — a seção do dia, incluindo o que é nosso apagar. O sentinel é conhecido
  aqui (`sentinel?`), não recopiado por quem precisa dele.
- `Todos::Repositories::NotionSchema.name_of(role)` / `.label_of(role, value)` /
  `.value_of(role, label)` — propriedades por papel de domínio (`:status`,
  `:origin`, `:snoozed`); o nome literal do Notion existe uma vez só.
- `Todos::Repositories::TodoDatabase#notification_candidates` / `#create(title,
  origin:)` — o database To-Dos; leitura e escrita derivam do `NotionSchema`.
