# Notion como frontend e fonte da verdade do Tracker

O Tracker era um daemon com painel web (ERB) e SQLite como fonte da verdade. Decidimos
substituir o frontend tradicional pelo **Notion**: os Databases do Notion são a UI da
fila de atenção **e** a fonte da verdade dos To-Dos — o engenheiro edita direto no
Notion, e o backend (Rails, API mínima + worker) foca só em regras de negócio
(ciclo de notificação, snooze, fila) e integrações futuras (Jira, 1-on-1), lendo e
escrevendo nas pages do Database.

## Considered Options

- **Webhook** para detectar mudanças no Notion: rejeitado — exige endpoint público com
  SSL (localhost não é alcançável), e para ferramenta interna single-user expor o
  backend só para receber webhook é custo de infra sem retorno. Webhooks também são
  *at-most-once* (8 tentativas com backoff, ~24h) — a própria Notion recomenda re-buscar
  dados via API, pois o webhook é só sinal.
- **SQLite como fonte da verdade, Notion como espelho**: rejeitado — duplica o estado e
  obriga a sincronizar nos dois sentidos; o objetivo era simplificar.
- **Gem da comunidade** (`notion-ruby-client`): rejeitado — a superfície usada é pequena
  (query + create/update page); HTTP puro (Faraday/net-http) no adapter, sem dependência
  de terceiro no meio do seam.

## Consequences

- `app/views/`, rotas web, PWA e ActiveRecord para To-Dos são removidos; o backend
  expõe só o health check (`/up`). Sobra um processo de worker + HTTP mínimo.
- O backend roda **local**, na máquina do engenheiro — a notificação nativa do S.O.
  (`notify-send`/`osascript`/toast) só funciona onde o S.O. está, e é o propósito
  central do produto (quebrar hiperfoco).
- A detecção de mudanças é **polling incremental** no ciclo que já existe
  (`last_edited_time` como sort/filtro, paginação por cursor); rate limit 180 req/min
  por integration é folgado para o volume de um painel de To-Do.
- O Database "To-Dos" é criado **manualmente** no Notion; o backend valida as
  propriedades contra o schema esperado no boot e falha cedo se divergir.
- O `TodoRepository` preserva a interface (mesmos métodos para os use cases); o
  **adapter** troca de ActiveRecord para o cliente Notion — os use cases e seus testes
  (via fake in-memory) sobrevivem intactos. *(Atualização: hoje o adapter é
  `Todos::Repositories::TodoDatabase`, um módulo só para o database — leitura e
  escrita derivam do mesmo `NotionSchema`. A interface dos use cases continua
  pequena: `notification_candidates` e `create`.)*
- Os domínios futuros (Tracking, OneOnOnes) também **escrevem tudo no Notion**
  (`Origem: Via Jira` / `Via transcrição`), nunca no banco local.
