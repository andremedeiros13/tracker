# Contexto: Tracking

Bounded context para o rastreio de entregas diárias.

## O que este contexto receberá

- **Coleta de cards do Jira**: movimentados pelo usuário no dia (changelog REST API:
  `GET /rest/api/3/issue/{id}/changelog`, filtrando `author.accountId` + dia)
- **Rastreio do campo Reviewer**: **JQL history não alcança custom fields** (limitação
  documentada) — rastreável só via changelog REST API filtrando
  `items[].fieldId == customfield_XXXXX`, descoberto por
  `GET /rest/api/3/field/search?type=custom&query=Reviewer`
- **Commits e PRs do GitHub**: `is:pr author:@me`, `is:pr reviewed-by:@me` + datas;
  reviews via `GET /repos/{owner}/{repo}/pulls/{n}/reviews` (filtro client-side por
  `user.login` — não existe endpoint "reviews by user")
- **Use case nomeado**: `DiscoverReviewer` (e `CollectMovedIssues`, `CollectPullRequests`)
- **Relatório diário**: compilar entregas do dia, persistir (SQLite)

## Fontes de verdade

- Pesquisa completa: branch `research/pesquisa-jira-github`,
  `.scratch/wayfinder-tracker/research/pesquisa-jira-github.md`
- PRD §3.1 (requisitos), wayfinder map issues #2 e #4
