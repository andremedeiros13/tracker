# frozen_string_literal: true

module OneOnOnes
  module Repositories
    # Adapter Notion da page 1-on-1 (page, não database — ADR 0001): appenda
    # header do dia + título da reunião + resumo + action items. A leitura da
    # seção do dia vem de Tracker::Notion::PageDays (mesma varredura do Brag);
    # a escrita é própria — este repositório nunca apaga, o Brag sim.
    class MeetingRepository
      def initialize(client: Tracker::Notion::Client.from_env,
                     page_id: ENV.fetch("TRACER_NOTION_ONE_ON_ONES_PAGE_ID"),
                     page_days: nil)
        @client = client
        @page_id = page_id
        @page_days = page_days || Tracker::Notion::PageDays.new(client:, page_id:)
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
        @page_days.header_exists?(date)
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
          type: "bulleted_list_item",
          bulleted_list_item: {
            rich_text: [ { type: "text", text: { content: "#{marcador} [#{item.owner}] #{item.description}" } } ]
          }
        }
      end

      def data_do_dia(date)
        Tracker::Notion::PageDays.marker(date)
      end
    end
  end
end
