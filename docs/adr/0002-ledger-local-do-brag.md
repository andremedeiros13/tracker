# Ledger local dos blocos gerados no Brag document

O Brag document é **reconstruído**, não appendado: a cada ciclo a seção do dia é
apagada e reescrita inteira (o valor do dia só se conhece quando ele acaba — o
PR das 11h pode mergear às 18h). Reconstruir exige saber **o que é nosso** para
apagar: sem essa informação, o Tracker ou não limpa a seção (e duplica o
conteúdo a cada ciclo) ou apaga um parágrafo escrito à mão pelo engenheiro.

Guardamos um ledger local em `storage/tracking/brag_state.json` com os ids que
o Tracker criou, por dia, mais a assinatura do conteúdo renderizado de cada um.

## Considered Options

- **Varredura por convenção a cada ciclo** (achar o header do dia e apagar tudo
  abaixo do sentinel): rejeitado como caminho normal — custa um GET de todos os
  blocks da página a cada 30 min, e é destrutivo por construção: qualquer coisa
  escrita abaixo do sentinel seria apagada. Fica só como *fallback* para quando
  o ledger some, e mesmo assim só assume posse se o sentinel estiver lá.
- **Guardar o conteúdo no Notion** (hash numa propriedade): rejeitado — a page
  do Brag não é um database; criar uma propriedade só para metadado de
  integração polui o documento que o humano lê.
- **Nada local, só a convenção + sentinel**: rejeitado — a assinatura é o que
  permite o ciclo sem novidade não fazer **nenhum** request de escrita
  (`:sem_mudanca`), que é o que torna aceitável rodar de 30 em 30 minutos.

## Consequences

- O ledger **não é estado de domínio**: ele não descreve a entrega, descreve
  *quem escreveu o quê* na página. O Notion continua sendo a fonte da verdade
  do documento; o ledger é descartável — apagá-lo degrada para o fallback por
  convenção, nunca perde conteúdo gerado (o rebuild reescreve).
- A assinatura é um hash do bloco renderizado (sem `object`, que é constante).
  Mudou o formato do Brag, todas as assinaturas mudam e o dia é reescrito uma
  vez — comportamento desejado.
- Escrita é atômica (tmp + rename) e serializada por `flock` entre o daemon e
  um `rake` rodando junto. Falha de ledger é logada e não derruba o ciclo.
- O ledger é por `page_id`: trocar a página do Brag invalida o ledger antigo
  em vez de apagar blocks da página errada.
