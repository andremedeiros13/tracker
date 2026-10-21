# frozen_string_literal: true

module Tracking
  module Repositories
    # Adapter Notion do Brag document (page, não database — ADR 0001): lê os
    # blocks existentes (fonte do dedup) e appenda header do dia + bullets
    # com link clicável (decisão #12).
    class BragDocumentRepository
      def initialize(client: Tracker::Notion::Client.from_env,
                     page_id: ENV.fetch("TRACER_NOTION_BRAG_PAGE_ID"))
        @client = client
        @page_id = page_id
      end

      # Entregas já registradas no dia — dedup por external_id embutido no
      # bullet ("[Jira] Movido [ENG-123:10001:status] Descrição" — o id é o
      # último segmento [..] antes da descrição; contrato do formato).
      def entregas_existentes(day)
        bullets_do_dia(marcador_do_dia(day)).filter_map do |block|
          texto = texto_do(block)
          next unless (id = external_id_do(texto))

          { external_id: id, texto: texto }
        end
      end

      # Appenda o header do dia (se ainda não existe) e os bullets novos.
      def append(day, entregas)
        return if entregas.empty?

        children = []
        children << header_do_dia(day) unless header_existe?(day)
        children.concat(entregas.map { |entrega| bullet_da(entrega) })
        @client.append_block_children(@page_id, children)
      end

      private

      # Bullets do dia alvo: os que vêm depois do header marcado com o dia,
      # até o próximo header. Header sem o marcador fecha a janela.
      def bullets_do_dia(marcador)
        dentro = false
        @client.block_children(@page_id).filter_map do |block|
          tipo = block.fetch("type")
          next unless tipo == "heading_2" || tipo == "bulleted_list_item"

          if tipo == "heading_2"
            dentro = texto_do(block).include?(marcador)
            next
          end
          block if dentro
        end
      end

      def header_existe?(day)
        @client.block_children(@page_id).any? do |block|
          block.fetch("type") == "heading_2" && texto_do(block) == marcador_do_dia(day)
        end
      end

      def header_do_dia(day)
        {
          object: "block",
          type: "heading_2",
          heading_2: { rich_text: [ { type: "text", text: { content: marcador_do_dia(day) } } ] }
        }
      end

      def bullet_da(entrega)
        {
          object: "block",
          type: "bulleted_list_item",
          bulleted_list_item: {
            rich_text: [
              { type: "text", text: { content: "#{rotulo_da(entrega)} [#{entrega.external_id}] " } },
              { type: "text", text: { content: entrega.title.sub(/\A[^:]+:\s*/, ""), link: { url: entrega.url } } }
            ]
          }
        }
      end

      # Formato do bullet (decisão #12): fonte clicável + descrição.
      def rotulo_da(entrega)
        prefixo = { jira: "[Jira]", github: "[GitHub]" }.fetch(entrega.source, "[?]")
        sufixo = { card_movido: "Movido", reviewer: "Reviewer", pr_aberto: "PR aberto",
                   review: "Review", commit: "Commit" }.fetch(entrega.kind, "")
        "#{prefixo} #{sufixo}"
      end

      def marcador_do_dia(day)
        day.strftime("%d/%m/%Y")
      end

      def texto_do(block)
        block.fetch(block.fetch("type")).fetch("rich_text").map { |t| t.fetch("plain_text") }.join
      end

      # O external_id é o segmento [..] depois do rótulo ("[Jira] Movido [ID]
      # ...") — scan dos bracketed: o 1º é o rótulo da fonte, o 2º é o id.
      def external_id_do(texto)
        segmentos = texto.scan(/\[([^\]]+)\]/).flatten
        segmentos[1] if segmentos.size >= 2
      end
    end
  end
end
