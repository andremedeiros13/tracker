# Contexto: Tracking

Bounded context para o rastreio de entregas diárias — coleta o que o engenheiro
entregou no dia (Jira + GitHub) e appenda no Brag document (page no Notion, via
API de blocks — ADR 0001).

## O que este contexto faz

- **Coleta de cards do Jira**: movimentados pelo usuário no dia (changelog REST API:
  `GET /rest/api/3/issue/{id}/changelog`, filtrando `author.accountId` + dia)
- **Rastreio do campo Reviewer**: **JQL history não alcança custom fields** (limitação
  documentada) — rastreável só via changelog REST API filtrando
  `items[].fieldId == customfield_XXXXX` (id via ENV `JIRA_REVIEWER_FIELD_ID`,
  descoberto por `GET /rest/api/3/field/search?type=custom&query=Reviewer`;
  sem ENV, o rastreio é pulado sem erro)
- **Commits e PRs do GitHub**: `is:pr author:@me`, `is:pr reviewed-by:@me` + datas;
  reviews via `GET /repos/{owner}/{repo}/pulls/{n}/reviews` (filtro client-side por
  `user.login` — não existe endpoint "reviews by user")
- **Use cases**: `RebuildDayReport` (o ciclo — coleta, agrega e manda o Brag
  reescrever), `BuildDayReport` (regra pura do dia), `DiscoverReviewer` (rake
  task); `CollectMovedIssues`/`CollectPullRequests` (coletas dentro dos adapters)
- **Módulo da seção**: `Tracking::BragDocument` — recebe o `DayReport` e cuida
  de header, sentinel, ledger, lock e escrita. O chamador não monta bloco nem
  consulta o ledger: a interface é `rewrite(day, report)` / `preview(day,
  report)` / `adopt(day)` / `forget(days)`. O `preview` é a mesma copy em
  texto — o dono do formato responde pelas duas formas, e o `dry_run` do
  `RebuildDayReport` não tem traversal próprio
- **O que o adapter entrega é entity, não payload**: `JiraDayRepository`
  devolve `Entities::Card` e `Entities::Activity` — `mine` já resolvido, sem
  `fields`/`status_category`/`accountId`. É o mesmo contrato do
  `GitHubDayRepository` (que já devolvia `PullRequest`/`Commit`/`GivenReview`).
  A forma do payload do Jira morre no adapter, como a do bulkfetch já morria
- **A identidade é resolvida no adapter**: `JIRA_ACCOUNT_ID` é lido uma vez e
  vira `mine` no card e em cada atividade. O `BuildDayReport` não recebe mais
  account id — duas camadas não decidem mais a mesma coisa
- **Copy do documento é do renderer**: o adapter entrega estado de domínio
  (`:approved`); `Renderers::BragBlocks` traduz para "Aprovado" e falha alto em
  estado desconhecido. O mesmo vale para a linha de review anexada a um card:
  o `WorkItem` guarda as reviews, não o texto delas
- **Leitura da seção**: `Tracker::Notion::PageDays#section(day)` devolve
  `Section` (`day`, `header_id`, `body`, `body_ids`, `last_id`), não blocos.
  `PageDays.day_of`/`.text_of`/`.marker` são funções de módulo — o formato de
  data e a extração de texto existem uma vez só, para o Brag e o 1-on-1
- **Append no Brag document**: reconstrução com dedup — a cada ciclo a seção do
  dia é reescrita inteira (o valor do dia só se conhece quando ele acaba);
  header por dia (`heading_2` com a data), bullets com link clicável
  (decisão #12). O ledger local guarda só os ids que geramos, para apagar o
  nosso sem tocar no que foi escrito à mão
- **Ordem do documento**: decrescente — o dia mais recente fica no topo. Um dia
  novo entra no topo; um dia no meio entra depois do fim da seção do próximo dia
  mais novo; um backfill mais antigo que todos entra no fim. Cada seção tem o
  seu próprio sentinel, logo abaixo do header: é ele que delimita a seção e
  impede a escrita de um dia de cair dentro de outro

## Fontes de verdade

- Pesquisa completa: branch `research/pesquisa-jira-github`,
  `.scratch/wayfinder-tracker/research/pesquisa-jira-github.md`
- PRD §3.1 (requisitos), wayfinder map issues #2 e #4, formato do relatório
  decidido no issue #11 (tudo do PRD, snapshot, org inteira, histórico navegável)
