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
- **Use cases**: `CollectTodaysDeliveries` (o ciclo — agrega e appenda com dedup),
  `DiscoverReviewer` (rake task), `CollectMovedIssues`/`CollectPullRequests`
  (coletas dentro dos adapters)
- **Append no Brag document**: incremental com dedup — cada ciclo coleta o dia e
  appenda só entregas que ainda não estão (dedup por `external_id` embutido no
  bullet); header por dia (`heading_2` com a data), bullets com link clicável
  (decisão #12)

## Fontes de verdade

- Pesquisa completa: branch `research/pesquisa-jira-github`,
  `.scratch/wayfinder-tracker/research/pesquisa-jira-github.md`
- PRD §3.1 (requisitos), wayfinder map issues #2 e #4, formato do relatório
  decidido no issue #11 (tudo do PRD, snapshot, org inteira, histórico navegável)
