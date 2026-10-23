# Tracker

Daemon em Ruby/Rails no host do engenheiro. Não é um app web: o **Notion é a UI
e a fonte da verdade** ([ADR 0001](docs/adr/0001-notion-como-frontend.md)), e o
processo só agenda ciclos — notificação nativa, rebuild do Brag document e
importação de 1-on-1.

@CONTEXT.md

## Comandos

```bash
bin/ci                     # o gate: rubocop + bundler-audit + brakeman + rspec
bundle exec rspec          # suíte (191 exemplos, ~1s, zero rede)
bin/rubocop                # usa .rubocop.yml explicitamente
bin/tracker                # daemon em production, sem porta HTTP
bin/start                  # debug: sobe o servidor em :3931 (a 3000 é de outro app)
bin/setup                  # gems + notificação de teste + valida schema do Notion
```

`bin/ci` começa por `bin/setup`, que dispara uma **notificação nativa de
teste** — espere um toast do sistema no meio do gate. Para rodar as checagens
sem esse efeito, chame os passos direto (`bin/rubocop`, `bin/brakeman`,
`bin/bundler-audit`, `bundle exec rspec`).

Tarefas `rake` exigem o `.env` carregado à mão — o Rake não o lê:

```bash
set -a; . ./.env; set +a
rake tracking:preview[21/10/2026]   # imprime o dia sem escrever no Notion
rake tracking:rebuild               # reconstrói a seção do dia
rake one_on_ones:import
```

Ao usar `bin/rails runner`, exporte `TRACER_DISABLE_SCHEDULER=1`: sem isso o
boot dispara um ciclo inteiro junto com o seu comando.

## Armadilhas

- **`.env` precisa terminar com quebra de linha.** Sem o newline no fim, o
  `source` do zsh engole a última variável.
- **Escrita de blocos no Notion é `PATCH`** em `/v1/blocks/{id}/children`.
  `POST` no mesmo path responde `400 invalid_request_url` neste workspace.
- **O daemon em `production` não recarrega código.** Editar um arquivo não muda
  o comportamento até o systemd reiniciar o processo (ele reinicia em 5s após
  morrer). `MemoryMax=2G` no unit — um `Killed` sem traceback é OOM, não bug.
- **O schema do Notion é validado no boot** e falha cedo se divergir. Ao mudar
  uma propriedade, mude `Todos::Repositories::NotionSchema` (fonte única) — o
  mapper, o validador e a escrita derivam dela. Nenhum label literal.
- **RuboCop ignora `bin/*`** (`.rubocop.yml`); não "conserte" offenses lá.

## Testes

Specs não tocam rede nem banco: `config.use_active_record = false` e os
adapters entram por injeção. Use fakes in-memory com a mesma interface do
adapter real (ver `spec/domains/todos/use_cases/`), nunca `stub_request`.

## Onde ler o quê

- **Termo de domínio ou regra de negócio** → `GLOSSARY.md`; o detalhe de cada
  bounded context está em `app/domains/*/{CONTEXT,README}.md`.
- **Por que o Notion é a UI / por que o Brag é reconstruído** → `docs/adr/`.
- **Setup, distribuição, unit do systemd, ENV vars** → `README.md` e
  `.env.example` (as chaves estão lá com o comentário de cada uma).
- **Como contribuir, o que rodar antes de compartilhar** → `CONTRIBUTING.md`.

## Notion pelo MCP

O server `notion` está no escopo de **usuário** (`~/.claude.json`), lendo
`NOTION_TOKEN` do shell. Não há `.mcp.json` de projeto de propósito: um server
com o mesmo nome no escopo de projeto disputaria a resolução e, num shell onde
`NOTION_TOKEN` não esteja exportado, subiria sem token. Para usar a API do
Notion nesta máquina, garanta `export NOTION_TOKEN=...` (o mesmo valor de
`TRACER_NOTION_TOKEN` no `.env`).

## Convenções

- Comentários em **português** explicando **por quê** (não o quê). A interface
  pública é em inglês (`call`, `notification_candidates`, `rewrite`); os
  helpers internos costumam ser em português (`atividades_do_dia`,
  `bullets_do_resumo`). Siga o arquivo que estiver editando.
- Erros de integração derivam de `Tracker::Error`; o `Scheduler::Job` resgata
  cada job, então a falha de um não derruba o daemon nem os outros ciclos.
- Sem IA/LLM em nenhum parsing — requisito rígido do PRD. Todo parsing é nativo.
- Cross-platform desktop (Linux, macOS, Windows); notificação sempre pelo
  comando nativo do S.O.
