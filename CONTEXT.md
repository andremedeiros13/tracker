# Tracker

Ferramenta interna para engenheiros de software: rastreamento de entregas diárias,
histórico de 1-on-1 via transcrições, e To-Dos com **notificações nativas do S.O.**
para quebrar o estado de hiperfoco.

Termos que atravessam domínios e vocabulário de arquitetura: [GLOSSARY.md](GLOSSARY.md).

## Domínios (bounded contexts)

- **Todos** — painel de To-Do e ciclo de notificação. Glossário:
  `app/domains/todos/CONTEXT.md`
- **Frontend**: o Notion — os Databases do Notion são a UI da fila de atenção **e** a
  fonte da verdade ([ADR 0001](docs/adr/0001-notion-como-frontend.md)). Estrutura na
  page "Tracker": **To-Dos** (database, board por Status — o único database),
  **Brag document** (page — entregas diárias, headers por dia + bullets) e
  **1-on-1** (page — conversas contínuas, headers por data + callouts). Regra:
  gestão de fluxo vira database; registro/narrativa vira page
- **Tracking** — rastreio de entregas (Jira, commits/PRs) — futuro: append de bullet
  no Brag document via API de blocks
- **OneOnOnes** — parsing de transcrições de 1-on-1 — futuro: append do resumo na
  page 1-on-1 via API de blocks; o action item vira row no To-Dos

## Linguagem

- **To-Do (Tarefa)**: unidade de pendência, com origem e estado
- **Fila de atenção**: painel principal — pendências ordenadas pelo que vence primeiro
- **Snoozed**: lembrete silenciado até X; a tarefa continua na fila até ser concluída
- **Resumo único por ciclo**: 1 notificação nativa por ciclo com o count de pendências
- **Notificação nativa**: alerta do S.O. via comandos nativos (`notify-send` /
  `osascript` / PowerShell toast) — nunca notificação de browser
- **Origem**: `manual` | `via_jira` | `via_transcricao`
- **Detecção de mudanças**: polling incremental no ciclo do backend (`last_edited_time`
  + cursor) — nunca webhook (ADR 0001)

## Diretrizes

- **Sem IA/LLM**: todo parsing é nativo da aplicação (PRD, vige para todo o projeto)
- **Cross-platform desktop**: Linux, macOS, Windows (sem iPhone/push)
- Controllers thin; lógica de domínio em `app/domains/*/use_cases` com interface `.call`
