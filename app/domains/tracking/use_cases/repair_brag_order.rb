# frozen_string_literal: true

module Tracking
  module UseCases
    # Conserta o Brag document que ficou fora de ordem antes de 2026-10-23.
    #
    # Antes, a seção de um dia novo era inserida logo depois do sentinel — e o
    # sentinel procurado era o da página inteira, não o da seção. Resultado: o
    # conteúdo de cada dia novo caía DENTRO da seção do dia anterior, numa
    # página crescente. O rewrite corrige isso daqui pra frente; o que já está
    # lá precisa ser rearranjado uma vez.
    #
    # Regra de posse (a mesma do resto do módulo): só tocamos em block que está
    # no ledger, de qualquer dia. Um bloco escrito à mão não está em ledger
    # nenhum e é deixado onde está.
    #
    # É DESTRUTIVA (apaga header/sentinel/corpo e reconstrói). Por isso:
    #   - só roda por rake, nunca pelo scheduler;
    #   - dry-run por default — imprime o plano e não toca no Notion;
    #   - grava o texto atual de cada seção em storage/tracking/ antes.
    #
    # Reconstrói do mais novo para o mais antigo: a primeira seção entra no
    # topo e cada seguinte logo depois do fim da anterior, que é o que produz
    # a ordem decrescente.
    class RepairBragOrder
      def initialize(client: Tracker::Notion::Client.from_env,
                     page_id: ENV.fetch("TRACER_NOTION_BRAG_PAGE_ID"),
                     ledger: nil,
                     page_days: nil,
                     logger: Rails.logger,
                     stdout: $stdout,
                     apply: ENV["APPLY"] == "1")
        @client = client
        @page_id = page_id
        @ledger = ledger || Tracker::Brag::BlockLedger.new(page_id:)
        @page_days = page_days || Tracker::Notion::PageDays.new(client:, page_id:)
        @logger = logger
        @stdout = stdout
        @apply = apply
      end

      def call(days: nil)
        blocos = @page_days.blocks
        secoes = secoes_por_dia(blocos)
        alvos = (days || secoes.keys).sort.reverse

        if alvos.empty?
          @stdout.puts("Nenhuma seção de dia no Brag — nada a reparar.")
          return 0
        end

        imprimir_plano(blocos, secoes, alvos)
        return 0 unless @apply

        @ledger.with_lock do
          secoes.each { |dia, blocos_da_secao| backup(dia, blocos_da_secao) }
          apagar(blocos, secoes, alvos)
          alvos.each { |dia| @ledger.forget(dia) }
        end

        alvos.each { |dia| RebuildDayReport.new.call(dia) }
        @stdout.puts("Reparado: #{alvos.map { |d| Renderers::BragBlocks.data_do_dia(d) }.join(', ')}.")
        alvos.size
      end

      private

      # {Date => blocks da seção (header + corpo até o próximo header)}, na
      # ordem em que aparecem na página.
      def secoes_por_dia(blocos)
        @page_days.section_days(blocks: blocos).uniq.index_with do |dia|
          @page_days.section(dia, blocks: blocos)
        end
      end

      # Ids a apagar, por dia: o header e o sentinel da seção, os blocks que o
      # ledger daquele dia conhece, e os blocks que pertencem ao ledger de
      # OUTRO dia (os que caíram na seção errada). Bloco desconhecido fica.
      def ids_a_apagar(blocos, secoes, alvos)
        de_outro_dia = {}
        secoes.each_key do |dia|
          Array(@ledger.day(dia)&.dig(:blocks)).each { |b| de_outro_dia[b[:id]] = dia }
        end

        alvos.flat_map do |dia|
          secao = secoes[dia] || []
          do_dia = Array(@ledger.day(dia)&.dig(:blocks)).map { |b| b[:id] }
          sentinel = secao.select { |b| sentinel?(b) }.map { |b| b.fetch("id") }

          secao.filter_map do |b|
            id = b.fetch("id")
            next id if @page_days.header?(b)
            next id if sentinel.include?(id)
            next id if do_dia.include?(id)
            next id if de_outro_dia.key?(id) # está na seção errada

            nil
          end
        end.uniq
      end

      def apagar(blocos, secoes, alvos)
        ids = ids_a_apagar(blocos, secoes, alvos)
        @logger.info("[tracking] repair: apagando #{ids.size} block(s)")
        ids.each { |id| @client.delete_block(id) }
      end

      def imprimir_plano(blocos, secoes, alvos)
        @stdout.puts("== Brag: ordem atual ==")
        secoes.each_key { |dia| @stdout.puts("  #{Renderers::BragBlocks.data_do_dia(dia)}") }
        @stdout.puts("== Ordem pretendida (decrescente) ==")
        alvos.each { |dia| @stdout.puts("  #{Renderers::BragBlocks.data_do_dia(dia)}") }
        ids = ids_a_apagar(blocos, secoes, alvos)
        @stdout.puts("Blocks a apagar e reescrever: #{ids.size}")
        ids.each { |id| @stdout.puts("  - #{id}") }
        @stdout.puts("(dry-run — rode com APPLY=1 para aplicar)") unless @apply
      end

      def sentinel?(block)
        @page_days.block?(block, "paragraph") &&
          @page_days.text(block).include?(Renderers::BragBlocks::SENTINEL)
      end

      def backup(dia, blocos_da_secao)
        dir = Rails.root.join("storage/tracking")
        FileUtils.mkdir_p(dir)
        caminho = dir.join("brag_#{dia.iso8601}-antes-do-repair.bak")
        File.write(caminho, blocos_da_secao.map { |b| "#{b.fetch('type')}: #{@page_days.text(b)}" }.join("\n"))
        @stdout.puts("Backup: #{caminho}")
      end
    end
  end
end
