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
  consulta o ledger: a interface é `rewrite(day, report)` / `adopt(day)`
- **Normalização no adapter**: `JiraDayRepository` entrega `Entities::Activity`
  (autor, instante e itens de status já resolvidos). A diferença entre o
  bulkfetch (epoch ms, author como accountId) e o changelog individual (ISO
  8601, `{accountId:}`) morre ali — o domínio nunca vê
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
