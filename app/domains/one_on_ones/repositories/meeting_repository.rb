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
      #
      # IDEMPOTENTE por (dia, título): o import escreve na page e só depois
      # move o arquivo. Se algo falhar no meio, o arquivo fica na pasta e o
      # ciclo seguinte chama este método de novo — sem esta checagem, a mesma
      # reunião entrava duas vezes na page (e os To-Dos junto). O README
      # prometia "nunca re-importado"; a garantia tem de estar aqui, não só no
      # `mv`.
      #
      # Devolve true quando escreveu e false quando a reunião já estava lá —
      # quem chama usa isso para não re-criar os To-Dos dos action items.
      def append(meeting, action_items)
        secao = @page_days.section(meeting.date)
        return false if ja_importada?(secao, meeting)

        children = []
        children << header_do_dia(meeting.date) if secao.nil? || secao.empty?
        children << titulo_da(meeting)
        children.concat(bullets_do_resumo(meeting))
        children.concat(action_items.map { |item| bullet_do(item) })
        @client.append_block_children(@page_id, children)
        true
      end

      private

      # A reunião já está no histórico do dia? O título é o marcador: uma
      # reunião por título por dia (heading_3 dentro da seção do dia).
      def ja_importada?(secao, meeting)
        return false if secao.nil?

        secao.body.any? do |block|
          Tracker::Notion::PageDays.block?(block, "heading_3") &&
            Tracker::Notion::PageDays.text_of(block) == meeting.title
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
