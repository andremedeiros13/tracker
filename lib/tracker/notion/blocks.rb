# frozen_string_literal: true

module Tracker
  module Notion
    # A forma de um bloco da API do Notion — quem escreve e quem lê.
    #
    # Existe porque a forma era montada em dois lugares (o renderer do Brag e o
    # repositório do 1-on-1) e lida num terceiro, com um leitor defensivo que
    # aceitava os dois dialetos (`plain_text` vindo da API, `text.content`
    # vindo do renderer). Um dono só: quem escreve não escolhe o dialeto, e
    # quem lê não precisa adivinhar.
    #
    # O dialeto canônico é o que a API devolve: `type` em string, payload
    # indexado por símbolo. Mudar isso muda a assinatura do ledger e reescreve
    # o Brag inteiro uma vez (ADR 0002) — então a forma é mantida estável.
    module Blocks
      module_function

      # `heading_2` é o header de dia nas duas pages; `heading_3` é o título de
      # uma reunião dentro do dia (1-on-1).
      def heading(texto, nivel: 2)
        tipo = "heading_#{nivel}"
        { object: "block", type: tipo, tipo.to_sym => { rich_text: [ run(texto) ] } }
      end

      def paragrafo(texto, cor: nil, italico: false)
        { object: "block", type: "paragraph",
          paragraph: { rich_text: [ run(texto, cor:, italico:) ] } }
      end

      # O bullet é o único bloco que aceita filhos — os sub-bullets de
      # evidência do Brag e os action items da reunião são o mesmo tipo.
      # `runs` permite o texto quebrado em pedaços (link, negrito); o caso
      # comum é um pedaço só (ver `bullet_texto`). Sem filhos, a chave é
      # omitida (é o shape que a API espera para um bullet folha).
      def bullet(runs:, filhos: [])
        payload = { rich_text: Array(runs) }
        payload[:children] = filhos unless filhos.empty?
        { object: "block", type: "bulleted_list_item", bulleted_list_item: payload }
      end

      def bullet_texto(texto, filhos: [])
        bullet(runs: [ run(texto) ], filhos:)
      end

      # Um pedaço de rich text. `link` vai DENTRO de `text` — ao lado, a API
      # responde 400 ("rich_text[1].link should be not present").
      def run(texto, link: nil, negrito: false, cor: nil, italico: false)
        conteudo = { content: texto }
        conteudo[:link] = { url: link } if link

        anotacoes = {}
        anotacoes[:bold] = true if negrito
        anotacoes[:italic] = true if italico
        anotacoes[:color] = cor if cor

        bloco = { type: "text", text: conteudo }
        bloco[:annotations] = anotacoes if anotacoes.any?
        bloco
      end

      # Texto plano de qualquer bloco: o payload da API (`plain_text`, chaves
      # string) e o shape que este módulo escreve (`text.content`, chaves
      # símbolo). Os testes montam híbridos (type string, payload símbolo) e
      # este é o único lugar que precisa tolerar isso.
      def texto_de(bloco)
        tipo = tipo_de(bloco)
        runs = bloco.dig(tipo.to_sym, :rich_text) || bloco.dig(tipo, "rich_text") ||
               bloco.dig(tipo.to_sym, "rich_text") || bloco.dig(tipo, :rich_text)
        Array(runs).map do |t|
          t["plain_text"] || t.dig("text", "content") || t.dig(:text, :content).to_s
        end.join
      end

      # `heading_2` é o header de dia nas duas pages; `heading_3` é o título de
      # uma reunião dentro do dia (1-on-1).
      def tipo_de(bloco) = bloco[:type] || bloco.fetch("type")

      def heading?(bloco, nivel: 2) = tipo_de(bloco) == "heading_#{nivel}"
    end
  end
end
