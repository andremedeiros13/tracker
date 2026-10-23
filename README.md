# Tracker

> 🔔 To-Do no **Notion** com **notificações nativas do sistema** — para quebrar o
> hiperfoco e lembrar das pendências que importam.

Um daemon que roda no seu computador. Você gerencia as tarefas **no Notion**;
o daemon notifica você no intervalo configurado e automatiza três coisas:

1. **Notificações** — 1 lembrete por ciclo com o resumo das pendências
2. **Tracking** — suas entregas do dia (Jira + GitHub) registradas no Brag document
3. **1-on-1s** — transcrições do Meet importadas para o histórico no Notion

## Estrutura no Notion

Crie uma page "Tracker" com esta estrutura (é a única configuração no Notion):

```
📄 Tracker (page)
   ├── 🗂️ To-Dos (database — board por Status)   ← a fila de atenção
   ├── 📄 Brag document (page)                   ← entregas diárias, dia mais recente no topo
   └── 🗣️ 1-on-1 (page)                          ← histórico de conversas
```

O database **To-Dos** precisa destas propriedades:

| Propriedade | Tipo | Opções |
|---|---|---|
| `Name` | Title | — |
| `Status` | Status | `Pendente`, `Em andamento`, `Concluída` |
| `Origem` | Select | `Manual`, `Via Jira`, `Via Transcrição` |
| `Snoozed até` | Date | **com hora** (para snooze preciso) |

Depois, crie uma integration interna em
[notion.so/profile/integrations](https://www.notion.so/profile/integrations),
copie o token, e na page "Tracker" use **••• → Connections** para dar acesso.

## Instalação

```bash
git clone git@github.com:andremedeiros13/tracker.git
cd tracker

# copie o exemplo e preencha — a última linha PRECISA terminar com quebra de linha
cp .env.example .env
$EDITOR .env

bin/setup   # instala gems, valida o schema e dispara uma notificação de teste
bin/tracker   # sobe o daemon
```

> Os IDs das pages/database você pega no Notion: abra o item → **••• → Copy link**
> → o ID é o UUID no fim da URL. `JIRA_ACCOUNT_ID` vem de
> `https://SEU-JIRA/rest/api/3/myself` (campo `accountId`).

Sem as credenciais do Jira/GitHub, o Tracking é pulado sem erro — as notificações
funcionam só com o Notion.

## Uso diário

**A fila de atenção é o Notion.** Abra o database "To-Dos" (view em Board,
agrupado por `Status`) e edite direto nele:

- **Concluir** → arraste para `Concluída` (some da fila)
- **Snoozar** → arraste para `Em andamento` + preencha `Snoozed até` com horário
  no futuro (silencia o lembrete até o horário vencer)

O daemon roda em segundo plano, **sem abrir porta** (não sobe servidor HTTP). Cada
job tem a própria cadência: notificação a cada 45 min (09:00–18:00), Tracking a
cada 30 min (08:00–23:50) e uma varredura larga do Jira por dia. Tudo configurável
com `TRACER_*`.

> Se precisar do servidor para debug, use `bin/start` — ele escuta em
> **http://localhost:3931/up** (porta própria; a 3000 é de outras aplicações).

### 1-on-1: solte o .md do Meet na pasta `one_on_ones/`

A pasta **já vem com o projeto**, na raiz do repo (o conteúdo é ignorado pelo git).
Solte nela o .md do Meet ("Anotações do Gemini") — o daemon importa sozinho no ciclo:

- O **resumo** vai para a page 1-on-1 (header do dia, título, resumo, action items)
- Os **action items seus** (matching parcial com `TRACER_ONE_ON_ONES_ME`) viram
  rows no To-Dos com origem `Via Transcrição`
- O arquivo importado vai para `one_on_ones/importados/` — nunca re-importado

### Tracking: o dia no Brag document

A cada ciclo o daemon **reconstrói** o dia no Brag document (não appenda: um PR
aberto às 11h e mergeado às 18h precisa aparecer como mergeado). Um item por
card, com estado, métricas do PR e o "Antes/Fiz" tirado do corpo do PR:

```
## 21/10/2026 — quarta · [Motor][Wave2] Pagamento com até 3 cartões
• #2301 · [Payments] T11 POST /payments/{id}/capture — MERGEADO 16:48
    PR #1216 · 14 commits · 17 arquivos · +1257/−55 · mergeado 16:48
    aprovado por marivaldo
    Antes: a rota respondia 204 e não gravava nada…
    Fiz: grava a solicitação e chama o provedor no próprio HTTP…
• #2332 · [RDMerchant] T20 captured_at da Bill — card de Itallo
    Review → Ready for Deploy
```

- **Jira**: cards em que você participou (filtro estreito, ~0,5 s por ciclo)
- **GitHub**: seus PRs (abertos e mergeados no dia), reviews que você deu, commits
- Um card de outra pessoa que você só moveu aparece como `card de Fulano` — nunca
  como sua entrega; higiene de board (`Prioritized → To Do`) não aparece

O trecho gerado fica sob um aviso cinza ("gerado pelo Tracker — edições neste
trecho são sobrescritas"). Blocos que **você** criar na seção não são tocados.

## Comandos

```bash
bin/tracker                        # sobe o daemon (sem servidor HTTP, production)
bin/start                          # sobe com servidor HTTP em :3931 (debug)
rake tracking:preview[21/10/2026]  # imprime o dia SEM escrever no Notion
rake tracking:rebuild[21/10/2026]  # reconstrói a seção do dia agora
rake tracking:adopt[21/10/2026]    # migra uma seção no formato antigo (uma vez)
rake tracking:repair_order         # conserta o Brag fora de ordem (dry-run; APPLY=1 aplica)
rake tracking:discover_reviewer    # acha o id do customfield Reviewer no Jira
rake one_on_ones:import            # importa as transcrições agora
```

> O `rake` não carrega o `.env` — rode antes: `set -a; source .env; set +a`

## Quando algo não entra no Notion

O daemon é silencioso no sucesso; falha aparece no log, com o nome do job:

```bash
journalctl --user -u tracker.service -f  # ticks, falhas, boot, OOM e reinício
tail -f log/development.log              # quando você roda via rake/console
```

Cada job resgata o próprio erro: uma falha no Tracking não impede a notificação
nem a importação de 1-on-1. Um `tick` no journal diz quais jobs rodaram; ausência
de tick há mais de uma hora significa daemon parado.

Se o processo morrer sem traceback (`Killed`), foi o teto de memória do unit
(`MemoryMax=2G`) e o systemd reinicia em 5s — o reinício também pega código
novo, então editar o código sem reiniciar não muda o comportamento.

## Rodar no login (opcional, recomendado)

Se o daemon não sobe no login, você precisa lembrar de iniciar — o que mata o
propósito.

<details>
<summary><b>Linux (systemd user unit)</b></summary>

```bash
cp dist/tracker.service ~/.config/systemd/user/
# Ajuste o WorkingDirectory no arquivo se o repo não estiver em ~/Repositories/tracker
systemctl --user daemon-reload
systemctl --user enable --now tracker.service

# (opcional) sobreviver ao logout:
sudo loginctl enable-linger $USER
```

Logs: `journalctl --user -u tracker.service -f`

O unit roda com PATH mínimo, então o `bin/tracker` resolve o Ruby sozinho: se houver
asdf (`~/.asdf`), ele lê o `.tool-versions` e usa o Ruby de lá. Com outro version
manager (rbenv, mise…), ajuste o PATH no `bin/tracker` ou exporte no unit.

</details>

<details>
<summary><b>macOS (LaunchAgent)</b></summary>

Crie `~/Library/LaunchAgents/com.tracker.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.tracker</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-c</string>
    <string>cd ~/Repositories/tracker &amp;&amp; ./bin/tracker</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.tracker.plist
```

</details>

<details>
<summary><b>Windows (Tarefa agendada)</b></summary>

No PowerShell (como seu usuário):

```powershell
$action = New-ScheduledTaskAction -Execute "powershell" `
  -Argument "-NoProfile -Command cd $HOME\Repositories\tracker; ./bin/tracker"
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName "Tracker" -Action $action -Trigger $trigger
```

</details>

---

## Contribuir

```bash
bundle exec rubocop        # lint + formatação
bundle exec rspec          # specs (fakes/stubs — zero rede)
bundle exec brakeman       # security scan
```

Decisões de design: [ADR 0001 — Notion como frontend](docs/adr/0001-notion-como-frontend.md).
Estrutura do código: [CONTRIBUTING.md](CONTRIBUTING.md).

<sub>Rails 8 · daemon no host · Notion como frontend e fonte da verdade · notificações nativas</sub>
