# frozen_string_literal: true

module Tracking
  module Repositories
    # Adapter Notion do Brag document (page, não database — ADR 0001).
    #
    # O documento é RECONSTRUÍDO, não appendado: o valor do dia só se conhece
    # quando o dia acaba (o PR das 11h pode mergear às 18h), então append
    # incremental congela o registro no primeiro ciclo e mostra "PR aberto"
    # para sempre. A cada mudança, a seção do dia é reescrita inteira.
    #
    # Quem manda apagar é o ledger (lib/tracker/tracking/block_ledger.rb):
    # só os ids que nós criamos. Um bloco escrito à mão na seção não está no
    # ledger e nunca é tocado. Sem ledger confiável, cai no fallback por
    # convenção — que só assume posse quando o sentinel está lá.
    class BragDocumentRepository
      # Teto de children por chamada da API do Notion.
      LOTE_DE_BLOCKS = 100

      def initialize(client: Tracker::Notion::Client.from_env,
                     page_id: ENV.fetch("TRACER_NOTION_BRAG_PAGE_ID"),
                     ledger: nil,
                     logger: Rails.logger)
        @client = client
        @page_id = page_id
        @ledger = ledger || Tracker::Brag::BlockLedger.new(page_id: page_id)
        @logger = logger
      end

      # Reescreve a seção do dia.
      #
      # Devolve :sem_mudanca quando a assinatura de todos os itens bate com o
      # ledger — nesse caso NENHUM request de escrita acontece (é o que faz um
      # ciclo de 30 min sem novidade custar quase nada).
      #
      # `blocos` são os blocos do corpo já renderizados (sem header/sentinel).
      # Header e sentinel são criados uma vez e nunca apagados.
      def rebuild(day, header:, sentinel:, blocos:)
        estado = @ledger.day(day)
        assinaturas = blocos.map { |bloco| Renderers::BragBlocks.signature(bloco) }
        return :sem_mudanca if inalterado?(estado, assinaturas)

        header_id = estado&.dig(:header_id) || achar_header(day) || criar(header)
        sentinel_id = estado&.dig(:sentinel_id) || criar(sentinel, after: header_id)

        apagar_do_dia(estado)
        criados = escrever(blocos, after: sentinel_id)
        @ledger.record(day, header_id: header_id, sentinel_id: sentinel_id,
                            blocks: criados.each_with_index.map { |id, i| { id: id, signature: assinaturas[i] } })
        :reescrito
      end

      # Blocks da seção de um dia (header + tudo até o próximo header). Usado
      # pela migração única (AdoptBragSection) — o rebuild normal não varre a
      # página quando o ledger está em dia.
      def blocos_do_dia(day)
        marcador = Renderers::BragBlocks.data_do_dia(day)
        dentro = false
        @client.block_children(@page_id).select do |block|
          if block.fetch("type") == "heading_2"
            dentro = texto_do(block).start_with?(marcador)
            dentro
          else
            dentro
          end
        end
      end

      private

      def inalterado?(estado, assinaturas)
        return false if estado.nil?

        Array(estado[:blocks]).map { |b| b[:signature] } == assinaturas
      end

      # Ano + data do header, procurado no documento — usado quando o ledger
      # sumiu mas o header (criado por nós antes) continua na page.
      def achar_header(day)
        marcador = Renderers::BragBlocks.data_do_dia(day)
        @client.block_children(@page_id).find do |block|
          block.fetch("type") == "heading_2" && texto_do(block).start_with?(marcador)
        end&.fetch("id")
      end

      def criar(bloco, after: nil)
        @client.append_block_children(@page_id, [ bloco ], after:).fetch("results").first.fetch("id")
      end

      # Apaga só o que está no ledger. `delete_block` trata 404 como sucesso
      # (o bloco pode ter sido apagado à mão no Notion). O DELETE do pai leva
      # os filhos junto (verificado contra a API em 2026-10-21).
      def apagar_do_dia(estado)
        Array(estado&.dig(:blocks)).each do |bloco|
          @client.delete_block(bloco.fetch(:id))
        rescue Tracker::Notion::ApiError => e
          @logger.warn("[tracking] não deu para apagar block #{bloco[:id]}: #{e.message}")
        end
      end

      # Escreve em lotes de 100. Cada lote entra DEPOIS do último bloco criado
      # (não sempre depois do mesmo `after`, senão o segundo lote cairia antes
      # do primeiro e o dia sairia em ordem invertida).
      def escrever(blocos, after:)
        ids = []
        blocos.each_slice(LOTE_DE_BLOCKS) do |lote|
          resposta = @client.append_block_children(@page_id, lote, after:)
          novos = Array(resposta["results"]).map { |b| b.fetch("id") }
          ids.concat(novos)
          after = novos.last
        end
        ids
      end

      def texto_do(block)
        block.fetch(block.fetch("type")).fetch("rich_text").map { |t| t.fetch("plain_text") }.join
      end
    end
  end
end
