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
    # A posse dos blocks é do módulo da seção (Tracking::BragDocument,
    # `forget`), que já tem o lock, o resgate de erro por bloco e o backup.
    # Aqui fica só o plano: quais dias, em que ordem — e o backup, que é
    # específico desta migração.
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
      def initialize(brag: nil,
                     page_days: nil,
                     client: Tracker::Notion::Client.from_env,
                     page_id: ENV.fetch("TRACER_NOTION_BRAG_PAGE_ID"),
                     logger: Rails.logger,
                     stdout: $stdout,
                     apply: ENV["APPLY"] == "1")
        @brag = brag || Tracking::BragDocument.new(client:, page_id:, logger:, stdout:)
        @page_days = page_days || Tracker::Notion::PageDays.new(client:, page_id:)
        @logger = logger
        @stdout = stdout
        @apply = apply
      end

      def call(days: nil)
        secoes = @page_days.sections
        alvos = (days || secoes.map(&:day).compact).sort.reverse

        if alvos.empty?
          @stdout.puts("Nenhuma seção de dia no Brag — nada a reparar.")
          return 0
        end

        imprimir_plano(secoes, alvos)
        return 0 unless @apply

        secoes.each { |secao| backup(secao.day, secao.blocks) }
        # Apagar é do módulo da seção: só o que está no ledger, com resgate de
        # erro por bloco.
        @brag.forget(alvos)

        alvos.each { |dia| RebuildDayReport.new.call(dia) }
        @stdout.puts("Reparado: #{alvos.map { |d| Renderers::BragBlocks.data_do_dia(d) }.join(', ')}.")
        alvos.size
      end

      private

      def imprimir_plano(secoes, alvos)
        @stdout.puts("== Brag: ordem atual ==")
        secoes.each { |secao| @stdout.puts("  #{Renderers::BragBlocks.data_do_dia(secao.day)}") }
        @stdout.puts("== Ordem pretendida (decrescente) ==")
        alvos.each { |dia| @stdout.puts("  #{Renderers::BragBlocks.data_do_dia(dia)}") }
        @stdout.puts("Dias a esquecer e reconstruir: #{alvos.size}")
        @stdout.puts("(dry-run — rode com APPLY=1 para aplicar)") unless @apply
      end

      # Texto atual da seção, antes de apagar: o conteúdo antigo não é
      # recuperável pelo ledger depois. Nome distinto do backup do rewrite
      # para não sobrescrever o `.bak` da adoção.
      def backup(dia, blocos)
        dir = Rails.root.join("storage/tracking")
        FileUtils.mkdir_p(dir)
        caminho = dir.join("brag_#{dia.iso8601}-antes-do-repair.bak")
        File.write(caminho, blocos.map { |b| "#{b.fetch('type')}: #{Tracker::Notion::PageDays.text_of(b)}" }.join("\n"))
        @stdout.puts("Backup: #{caminho}")
      end
    end
  end
end
