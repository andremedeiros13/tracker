# Tracker

> 🔔 To-Do no **Notion** com **notificações nativas do sistema** — para quebrar o
> hiperfoco e lembrar das pendências que importam.

O Tracker roda como um **daemon no seu computador**: um processo de fundo que lê
seus To-Dos de um **Database do Notion** (a UI da fila de atenção **e** a fonte da
verdade — [ADR 0001](docs/adr/0001-notion-como-frontend.md)) e lembra você via
**notificações nativas** (Linux, macOS, Windows).

Você edita as tarefas direto no Notion; o backend foca só no **ciclo de
notificação**: 1 notificação por ciclo com o resumo das pendências
("3 pendências: via Jira, manual"), nunca uma por tarefa.

---

## ✅ Pré-requisitos

| Requisito | Como verificar |
|---|---|
| **Ruby 4.x** | `ruby --version` → precisa mostrar `4.0.x` ou superior |
| **Linux**: `notify-send` | `which notify-send` (já vem na maioria das distros) |
| **Notion Free** (ou superior) | a API funciona no plano Free — ver [Limites](https://developers.notion.com/reference/request-limits) |

<details>
<summary><b>Instalar o Ruby (só se você não tiver)</b></summary>

- **Linux (Debian/Ubuntu)**: `sudo apt install ruby-full`
- **macOS**: `brew install ruby` (ou use `asdf`/`rbenv`)
- **Windows**: [RubyInstaller](https://rubyinstaller.org/) (versão + Devkit)

</details>

---

## 🗂️ Setup do Notion (2 passos, uma vez só)

1. **Crie a page "Tracker"** e dentro dela o **Database "To-Dos"** com exatamente
   estas propriedades:

   | Propriedade | Tipo | Opções |
   |---|---|---|
   | `Name` | Title | — |
   | `Status` | Status | `Pendente`, `Em andamento`, `Concluída` |
   | `Origem` | Select | `Manual`, `Via Jira`, `Via Transcrição` |
   | `Snoozed até` | Date | **com hora** (para snooze preciso) |

   O boot valida o schema contra o esperado e **falha cedo** se divergir.
   (Na view do Database, mude para **Board** agrupado por `Status`.)

2. **Conecte a integration ao Database**: crie uma connection interna em
   [notion.so/profile/integrations](https://www.notion.so/profile/integrations),
   copie o token, e na page "Tracker" use o menu **••• → Connections** para dar acesso.

## 🚀 Instalação

```bash
# 1. Clone o repositório
git clone git@github.com:andremedeiros13/tracker.git
cd tracker

# 2. Configure as credenciais (export no shell ou .env — carregado pelo bin/start)
cat > .env <<'EOF'
TRACER_NOTION_TOKEN=secret_xxx
TRACER_NOTION_DATABASE_ID=xxx
TRACER_NOTIFY_INTERVAL_MINUTES=45
TRACER_NOTIFY_ACTIVE_START=09:00
TRACER_NOTIFY_ACTIVE_END=18:00
EOF

# 3. Setup — instala gems e testa as notificações
bin/setup
```

O `bin/setup` instala as dependências, valida o schema do Database no Notion e
**dispara uma notificação de teste** — se ela aparecer no seu sistema, tudo certo.
(No macOS/Windows, conceda a permissão quando o S.O. perguntar.)

## ▶️ Execução

```bash
bin/start
```

O daemon fica rodando em segundo plano: serve só o health check
(http://localhost:3000/up) e dispara o lembrete no intervalo configurado
(padrão: a cada 45 min, das 09:00 às 18:00).

**A fila de atenção é o Notion** — abra o Database "To-Dos" e veja suas pendências
no board agrupado por Status. Para concluir ou snoozar, edite direto no Notion:

- **Concluir** → `Status: Concluída` (some da fila)
- **Snoozar** → `Status: Em andamento` + `Snoozed até` com horário no futuro
  (silencia o lembrete; volta quando o horário vence)

A detecção de mudanças é **polling incremental** — dentro do intervalo, o daemon
lê as pages que mudaram e notifica.

### A estrutura no Notion (page "Tracker")

```
📄 Tracker (page)
   ├── 🗂️ To-Dos (child database — board por Status)  ← a fila de atenção (POC)
   ├── 📄 Brag document (child page)                   ← entregas diárias (módulo futuro)
   └── 🗣️ 1-on-1 (child page)                          ← conversas contínuas (módulo futuro)
```

- **To-Dos** é o único **database**: gestão de fluxo — arrasta o card entre colunas para
  mudar o estado, o daemon notifica no ciclo. O que é fluxo pede estrutura: cards, drag,
  filtro por Status.
- **Brag document** é uma **page** (não database): o registro do que você entregou —
  headers por dia, bullets por entrega. Log cronológico, não board. O módulo
  Tracking (futuro) adiciona o bullet via API de blocks; você narra o impacto à mão.
- **1-on-1** é uma **page** (não database): as conversas em formato contínuo —
  header da data, narrativa da conversa, action items em callout (que viram rows
  no To-Dos). O módulo OneOnOnes (futuro) faz o append do resumo da transcrição
  via API de blocks.

A regra: **o que é gestão de fluxo vira database; o que é registro ou narrativa vira
page** — cada formato segue o propósito.

---

## 🖥️ Rodar no login (opcional, recomendado)

Se o daemon não sobe no login, você precisa lembrar de iniciar — o que mata o
propósito. Registre-o para iniciar sozinho:

<details>
<summary><b>Linux (systemd user unit)</b></summary>

```bash
cp dist/tracker.service ~/.config/systemd/user/
# Ajuste o WorkingDirectory no arquivo se o repo não estiver em ~/Repositories/tracker
systemctl --user daemon-reload
systemctl --user enable --now tracker.service

# (opcional) fazer o daemon sobreviver ao logout:
sudo loginctl enable-linger $USER
```

Logs: `journalctl --user -u tracker.service -f`

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
    <string>cd ~/Repositories/tracker &amp;&amp; ./bin/start</string>
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
  -Argument "-NoProfile -Command cd $HOME\Repositories\tracker; ./bin/start"
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName "Tracker" -Action $action -Trigger $trigger
```

</details>

---

## 🧪 Qualidade (para contribuir)

```bash
bundle exec rubocop        # lint + formatação
bundle exec rspec          # specs (fakes/stubs — zero rede)
bundle exec brakeman       # security scan
```

Veja [CONTRIBUTING.md](CONTRIBUTING.md) para a estrutura do código.

## 🗺️ O projeto

- **Decisões**: [ADR 0001 — Notion como frontend](docs/adr/0001-notion-como-frontend.md)
  e [wayfinder map](https://github.com/andremedeiros13/tracker/issues/1)
- **Módulos futuros** (após a validação da POC): rastreio de entregas
  (Jira + commits/PRs) e parsing de transcrições de 1-on-1
- **Sem IA/LLM**: todo parsing é nativo da aplicação

---

<sub>POC · Rails 8 · daemon no host · Notion como frontend e fonte da verdade · notificações nativas</sub>
