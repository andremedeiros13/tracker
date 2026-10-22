# frozen_string_literal: true

module Tracking
  module UseCases
    # Migração única: marca a seção de um dia que já existe no Brag (escrita
    # no formato antigo, um bullet por evento) como gerada pelo Tracker, para
    # que o rebuild possa apagá-la e reescrever no formato novo.
    #
    # Só roda por rake, nunca pelo scheduler — é destrutiva. Antes de tocar no
    # Notion, grava o texto atual em storage/tracking/brag_<dia>.bak (o
    # conteúdo antigo não é recuperável pelo ledger depois).
    class AdoptBragSection
      def initialize(brag: nil, ledger: nil, logger: Rails.logger, stdout: $stdout)
        @brag = brag || Repositories::BragDocumentRepository.new
        @ledger = ledger || Tracker::Brag::BlockLedger.new(page_id: ENV.fetch("TRACER_NOTION_BRAG_PAGE_ID"))
        @logger = logger
        @stdout = stdout
      end

      def call(day)
        marcador = Renderers::BragBlocks.data_do_dia(day)
        blocos = @brag.blocos_do_dia(day)
        if blocos.empty?
          @stdout.puts("Nenhuma seção em #{marcador} — o rebuild cria uma nova.")
          return 0
        end

        backup(day, blocos)
        header = blocos.find { |b| b.fetch("type") == "heading_2" }
        body = blocos.reject { |b| b.equal?(header) }
        @ledger.record(day, header_id: header.fetch("id"), blocks: body.map { |b| { id: b.fetch("id") } })
        @stdout.puts("Seção de #{marcador} adotada (#{body.size} blocks). Backup em storage/tracking/.")
        body.size
      end

      private

      # Um bloco por linha: tipo + texto. O leitor quer o conteúdo antigo
      # legível para colar em outro lugar se precisar.
      def backup(day, blocos)
        dir = Rails.root.join("storage/tracking")
        FileUtils.mkdir_p(dir)
        caminho = dir.join("brag_#{day.iso8601}.bak")
        texto = blocos.map { |b| "#{b.fetch('type')}: #{texto_do(b)}" }.join("\n")
        File.write(caminho, texto)
        @stdout.puts("Backup: #{caminho}")
      end

      def texto_do(block)
        block.fetch(block.fetch("type")).fetch("rich_text").map { |t| t.fetch("plain_text") }.join
      end
    end
  end
end
