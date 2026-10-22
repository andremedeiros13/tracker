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
    #
    # A leitura da seção (achar header/sentinel, blocos abaixo do sentinel)
    # vem de Tracker::Notion::PageDays — o formato da data e a varredura da
    # page são os mesmos do 1-on-1. Só a escrita é local: este repositório pode
    # apagar o que o ledger conhece; o do 1-on-1 nunca apaga.
    class BragDocumentRepository
      # Teto de children por chamada da API do Notion.
      LOTE_DE_BLOCKS = 100

      def initialize(client: Tracker::Notion::Client.from_env,
                     page_id: ENV.fetch("TRACER_NOTION_BRAG_PAGE_ID"),
                     ledger: nil,
                     logger: Rails.logger,
                     page_days: nil)
        @client = client
        @page_id = page_id
        @ledger = ledger || Tracker::Brag::BlockLedger.new(page_id: page_id)
        @logger = logger
        @page_days = page_days || Tracker::Notion::PageDays.new(client:, page_id:)
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
        # Lock entre processos: o daemon e um rake rodando junto (ou dois ticks
        # sobrepostos) reescreviam a mesma seção em paralelo.
        @ledger.with_lock do
          estado = @ledger.day(day)
          assinaturas = blocos.map { |bloco| Renderers::BragBlocks.signature(bloco) }
          next :sem_mudanca if inalterado?(estado, assinaturas)

          header_id = estado&.dig(:header_id) || achar_header(day) || criar(header)
          sentinel_id = estado&.dig(:sentinel_id) || achar_sentinel(header_id) || criar(sentinel, after: header_id)

          # Sem ledger mas com sentinel, a seção é nossa: adota os blocos que
          # já estão lá a partir do sentinel (é o que impede o rebuild de
          # ACRESCENTAR uma cópia quando o ledger some/é apagado).
          adotar_sem_ledger(day, estado, header_id, sentinel_id) if estado.nil?

          apagar_do_dia(@ledger.day(day))
          criados = escrever(blocos, after: sentinel_id)
          @ledger.record(day, header_id: header_id, sentinel_id: sentinel_id,
                              blocks: pares(criados, assinaturas))
          :reescrito
        end
      end

      # Blocks da seção de um dia (header + tudo até o próximo header). Usado
      # pela migração única (AdoptBragSection) — o rebuild normal não varre a
      # página quando o ledger está em dia.
      def blocos_do_dia(day)
        @page_days.section(day)
      end

      private

      # Seção nossa (tem sentinel) mas o ledger sumiu: os blocos abaixo do
      # sentinel, até o próximo header, passam a ser propriedade nossa e serão
      # reescritos. O que estiver abaixo do sentinel é, por contrato, gerado —
      # quem escreve à mão escreve ANTES do sentinel ou num bloco próprio.
      def adotar_sem_ledger(day, estado, header_id, sentinel_id)
        return if estado

        ids = @page_days.ids_after(day, sentinel_id)
        return if ids.empty?

        @logger.warn("[tracking] ledger ausente para #{day.iso8601}: adotando #{ids.size} block(s) da seção")
        @ledger.record(day, header_id: header_id, sentinel_id: sentinel_id,
                            blocks: ids.map { |id| { id: id } })
      end

      # Liga id criado → assinatura do bloco que o originou. `zip` (não
      # each_with_index) para nunca gravar signature nil: se a API devolver
      # mais ids que blocos enviados, zip trunca em vez de inventar pares.
      def pares(criados, assinaturas)
        criados.zip(assinaturas).reject { |id, assinatura| assinatura.nil? || id.nil? }
               .map { |id, assinatura| { id: id, signature: assinatura } }
      end

      def inalterado?(estado, assinaturas)
        return false if estado.nil?

        Array(estado[:blocks]).map { |b| b[:signature] } == assinaturas
      end

      # Ano + data do header, procurado no documento — usado quando o ledger
      # sumiu mas o header (criado por nós antes) continua na page.
      def achar_header(day)
        @page_days.section(day).find { |block| @page_days.header?(block) }&.fetch("id")
      end

      def criar(bloco, after: nil)
        @client.append_block_children(@page_id, [ bloco ], after:).fetch("results").first.fetch("id")
      end

      # Sentinels já criados por tentativas anteriores (o ledger pode não ter o
      # id se uma escrita falhou no meio). Sem isso, cada ciclo falho deixava
      # mais um parágrafo "gerado pelo Tracker" na página.
      def achar_sentinel(_header_id)
        @page_days.blocks
                  .select { |b| @page_days.block?(b, "paragraph") && @page_days.text(b).include?(Renderers::BragBlocks::SENTINEL) }
                  .first&.fetch("id")
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
    end
  end
end
