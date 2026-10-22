# frozen_string_literal: true

module Tracker
  module Notion
    # Leitura de uma page que guarda registros por dia (Brag document, page
    # 1-on-1): cabeçalho `heading_2` com a data, seguido dos blocos do dia até
    # o próximo cabeçalho.
    #
    # Existe porque os dois repositórios varriam a page cada um do seu jeito —
    # `brag_document_repository` com collect até o próximo header,
    # `meeting_repository` com `any?` — e ambos reimplementavam a extração de
    # texto do block (três cópias no repo). O formato da data também vivia em
    # dois módulos.
    #
    # Só LEITURA é compartilhada: os dois têm modelos de posse diferentes (o
    # Brag pode apagar o que o ledger conhece; o 1-on-1 nunca apaga). Quem
    # escreve continua sendo cada repositório.
    class PageDays
      def initialize(client:, page_id:)
        @client = client
        @page_id = page_id
      end

      # Marcador do header de um dia. Fonte única do formato "dd/mm/aaaa".
      def self.marker(day) = day.to_date.strftime("%d/%m/%Y")

      # Blocos da seção de um dia, incluindo o header.
      # `prefixo: true` casa "21/10/2026 — quarta"; exato casa só a data
      # (formato do 1-on-1, que não põe dia da semana).
      def section(day, prefixo: true)
        marcador = self.class.marker(day)
        dentro = false
        blocks.select do |block|
          if header?(block)
            dentro = header_matches?(block, marcador, prefixo)
            dentro
          else
            dentro
          end
        end
      end

      def header_exists?(day) = section(day, prefixo: false).any? { |block| header?(block) }

      # Ids dos blocos da seção, na ordem, sem o header.
      def body_ids(day, prefixo: true)
        section(day, prefixo:).reject { |block| header?(block) }.map { |block| block.fetch("id") }
      end

      # Ids abaixo de um block (o sentinel), até o próximo header.
      def ids_after(day, block_id)
        viu = false
        section(day).each_with_object([]) do |block, ids|
          if block.fetch("id") == block_id
            viu = true
          elsif viu && !header?(block)
            ids << block.fetch("id")
          end
        end
      end

      # Texto plano de um block, qualquer que seja o tipo (paragraph, heading_2,
      # bulleted_list_item...). Única cópia no repo.
      def text(block) = text_of_type(block, block.fetch("type"))

      def block?(block, type) = block.fetch("type") == type

      def header?(block) = block?(block, "heading_2")

      def blocks
        @client.block_children(@page_id)
      end

      private

      def header_matches?(block, marcador, prefixo)
        texto = text(block)
        prefixo ? texto.start_with?(marcador) : texto == marcador
      end

      # Payload da API traz "plain_text"; o renderer/testes montam "text".
      def text_of_type(block, type)
        Array(block.dig(type, "rich_text") || block.dig(type, :rich_text)).map do |t|
          t["plain_text"] || t.dig("text", "content") || t.dig(:text, :content).to_s
        end.join
      end
    end
  end
end
