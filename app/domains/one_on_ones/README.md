# Contexto: OneOnOnes

Bounded context para o histórico de 1-on-1 e parsing de transcrições.

## O que este contexto receberá

- **Importação de arquivos**: transcrições exportadas do Google Meet
  ("Anotações do Gemini") — formato real verificado: **Markdown**, múltiplas
  reuniões por arquivo
- **Parser nativo (sem IA/LLM)**: a estrutura é regular e detectável sem IA —
  - Cabeçalho: data + título + convidados (mailto: links)
  - `### Resumo`, `### Decisões` — bullets dos temas
  - `### Próximas etapas` — **checkboxes Markdown** `- [ ] [Nome] Descrição: detalhe`
    — os action items já vêm estruturados, com responsável entre colchetes
  - `### Detalhes` + transcrição crua com timestamps e falantes identificados
- **Geração automática de action items**: converter checkboxes em To-Dos do contexto
  Todos (origem `via_transcricao`), atribuindo pelo nome entre colchetes
- **Use case nomeado**: `ParseTranscription` (e `ImportTranscription`, `ConvertActionItems`)

## Fontes de verdade

- Exemplos reais anexados no
  [ticket #3](https://github.com/andremedeiros13/tracker/issues/3) (fonte de verdade)
- PRD §3.2 (requisitos), wayfinder map issue #3
