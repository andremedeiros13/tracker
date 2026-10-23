# frozen_string_literal: true

module Tracker
  module Notion
    # Leitura de uma page que guarda registros por dia (Brag document, page
    # 1-on-1): cabeçalho `heading_2` com a data, seguido dos blocos do dia até
    # o próximo cabeçalho.
    #
    # A interface devolve `Section`, não blocos: "qual é a seção do dia" é a
    # pergunta que todo chamador fazia, e cada um a respondia combinando
    # predicados por conta própria. O texto de um bloco — que três módulos
    # reimplementavam — é uma função de módulo, porque não depende da page.
    #
    # Só LEITURA é compartilhada: os dois documentos têm modelos de posse
    # diferentes (o Brag pode apagar o que o ledger conhece; o 1-on-1 nunca
    # apaga). Quem escreve continua sendo cada repositório.
    class PageDays
      def initialize(client:, page_id:)
        @client = client
        @page_id = page_id
      end

      # Marcador do header de um dia. Fonte única do formato "dd/mm/aaaa" — a
      # escrita do Brag e a do 1-on-1 usam este mesmo formato.
      def self.marker(day) = day.to_date.strftime("%d/%m/%Y")

      # Data de um header (`dd/mm/aaaa`), ou nil se o texto não for uma data.
      # O header do Brag tem sufixo ("21/10/2026 — quarta · épico") e o do
      # 1-on-1 não; ler só o prefixo cobre os dois sem flag de formato.
      def self.day_of(block)
        return unless block?(block, "heading_2")

        # `match` (MatchData), não `string[regex]` — o colchete devolveria a
        # String inteira e os índices [1..3] virariam caracteres, não grupos.
        casamento = text_of(block).match(/\A(\d{2})\/(\d{2})\/(\d{4})/)
        return unless casamento

        Date.new(casamento[3].to_i, casamento[2].to_i, casamento[1].to_i)
      rescue Date::Error
        nil
      end

      # Texto plano de um block, qualquer que seja o tipo (paragraph, heading_2,
      # bulleted_list_item...). Única cópia no repo.
      def self.text_of(block)
        tipo = block.fetch("type")
        # Payload da API traz "plain_text"; o renderer/testes montam "text".
        Array(block.dig(tipo, "rich_text") || block.dig(tipo, :rich_text)).map do |t|
          t["plain_text"] || t.dig("text", "content") || t.dig(:text, :content).to_s
        end.join
      end

      def self.block?(block, type) = block.fetch("type") == type

      # Todas as seções da page, na ordem em que aparecem. `blocks:` permite
      # reaproveitar uma leitura já feita — o caminho de escrita do Brag lê a
      # page uma vez e consulta várias seções.
      def sections(blocks: self.blocks)
        secoes = []
        atual = nil
        blocks.each do |block|
          if self.class.day_of(block)
            atual = []
            secoes << atual
          end
          atual << block if atual
        end
        secoes.map { |blocos| Section.new(blocos) }
      end

      # A seção de um dia, ou nil.
      def section(day, blocks: self.blocks)
        sections(blocks:).find { |secao| secao.day == day.to_date }
      end

      def blocks
        @client.block_children(@page_id)
      end
    end
  end
end
