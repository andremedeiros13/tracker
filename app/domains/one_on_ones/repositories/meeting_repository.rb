# frozen_string_literal: true

module OneOnOnes
  module Repositories
    # Adapter Notion da page 1-on-1 (page, não database — ADR 0001): appenda
    # header do dia + título da reunião + resumo + action items. Mesmo padrão
    # do BragDocumentRepository (append + header por dia).
    class MeetingRepository
      def initialize(client: Tracker::Notion::Client.from_env,
                     page_id: ENV.fetch("TRACER_NOTION_ONE_ON_ONES_PAGE_ID"))
        @client = client
        @page_id = page_id
      end

      # Appenda a reunião no histórico: header do dia (se ainda não existe),
      # título (heading_3 — múltiplas reuniões por dia), resumo e os action
      # items (✅ meus — viraram To-Do; 👤 dos outros — só histórico).
      def append(meeting, action_items)
        children = []
        children << header_do_dia(meeting.date) unless header_existe?(meeting.date)
        children << titulo_da(meeting)
        children.concat(bullets_do_resumo(meeting))
        children.concat(action_items.map { |item| bullet_do(item) })
        @client.append_block_children(@page_id, children)
      end

      private

      def header_existe?(date)
        @client.block_children(@page_id).any? do |block|
          block.fetch("type") == "heading_2" && texto_do(block) == data_do_dia(date)
        end
      end

      def header_do_dia(date)
        {
          object: "block",
          type: "heading_2",
          heading_2: { rich_text: [ { type: "text", text: { content: data_do_dia(date) } } ] }
        }
      end

      def titulo_da(meeting)
        {
          object: "block",
          type: "heading_3",
          heading_3: { rich_text: [ { type: "text", text: { content: meeting.title } } ] }
        }
      end

      # Resumo: um parágrafo por tema (o texto do Meet já vem estruturado).
      def bullets_do_resumo(meeting)
        return [] if meeting.summary.blank?

        meeting.summary.split("\n").reject(&:blank?).map do |paragrafo|
          {
            object: "block",
            type: "paragraph",
            paragraph: { rich_text: [ { type: "text", text: { content: paragrafo.strip } } ] }
          }
        end
      end

      def bullet_do(item)
        marcador = item.mine? ? "✅" : "👤"
        {
          object: "block",
          type: "bulleted_list",
          bulleted_list: {
            rich_text: [ { type: "text", text: { content: "#{marcador} [#{item.owner}] #{item.description}" } } ]
          }
        }
      end

      def data_do_dia(date)
        date.strftime("%d/%m/%Y")
      end

      def texto_do(block)
        block.fetch(block.fetch("type")).fetch("rich_text").map { |t| t.fetch("plain_text") }.join
      end
    end
  end
end
