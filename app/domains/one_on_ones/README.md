# Contexto: OneOnOnes

Bounded context para o histórico de 1-on-1 e parsing de transcrições — importa
os .md do Meet ("Anotações do Gemini") soltos numa pasta monitorada, extrai
resumo + action items nativamente, appenda o resumo na page 1-on-1 (Notion, via
API de blocks — ADR 0001) e cria To-Dos dos action items do usuário (rows no
database To-Dos, origem "Via Transcrição").

## O que este contexto faz

- **Importação por pasta monitorada** (default: `one_on_ones/` na raiz do repo,
  commitada vazia — o conteúdo é ignorado pelo git; ENV `TRACER_ONE_ON_ONES_DIR`
  sobrepõe): o daemon importa sozinho os .md soltos nela; arquivo importado vai
  para `importados/` (nunca re-importado)
- **Parser nativo (sem IA/LLM)**: a estrutura é regular e detectável sem IA —
  - Cabeçalho: data + título + convidados (mailto: links)
  - `### Resumo`, `### Decisões` — bullets dos temas (viram o resumo)
  - `### Próximas etapas` — **checkboxes Markdown** `- [ ] [Nome] Descrição: detalhe`
    — os action items já vêm estruturados, com responsável entre colchetes
  - `### Detalhes` + transcrição crua — ignorados (ficam no arquivo original)
  - Meses abreviados pt-BR ("set." → "Sep" para o Date.parse)
- **Atribuição por nome** (matching parcial — ENV `TRACER_ONE_ON_ONES_ME`):
  "André Medeiros" casa "André Medeiros" e "André"; action items seus viram
  To-Dos, dos outros ficam no histórico (👤)
- **Histórico**: page 1-on-1 — header do dia, título da reunião (heading_3),
  resumo, action items (✅ meus / 👤 dos outros)
- **Use cases**: `ParseTranscription` (puro, sem IO), `ImportTranscription`
  (o ciclo — lê, parseia, appenda, cria To-Dos, move o arquivo)

## Fontes de verdade

- Exemplos reais anexados no
  [ticket #3](https://github.com/andremedeiros13/tracker/issues/3) (fonte de
  verdade; a transcrição real de 1:1 André/Spalenza é fixture da spec do parser)
- PRD §3.2 (requisitos), wayfinder map issue #14 (decisões: upload → pasta
  monitorada após o ADR 0001; revisão na UI → matching por nome)
