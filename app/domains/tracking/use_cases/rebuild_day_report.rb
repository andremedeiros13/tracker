# frozen_string_literal: true

module Tracking
  module UseCases
    # O ciclo do Tracking: coleta o dia (Jira + GitHub), agrega, renderiza e
    # reescreve a seção do Brag document.
    #
    # Reconstrução em vez de append: o dia só está completo quando acaba.
    # A coleta de cada fonte é resgatada em separado — Jira fora não pode
    # impedir o registro do GitHub (e vice-versa).
    #
    # Reconstrói hoje e, até o meio-dia, também ontem: o que foi mergeado
    # 00:30 ainda pertence ao dia anterior do ponto de vista de quem trabalhou.
    class RebuildDayReport
      MEIO_DIA = 12

      def initialize(jira: nil, github: nil, brag: nil, renderer: Renderers::BragBlocks.new,
                     logger: Rails.logger, dry_run: ENV["TRACER_DRY_RUN"] == "1",
                     filtro: ENV.fetch("TRACER_JIRA_FILTRO", "estreito"), stdout: $stdout,
                     ledger: nil)
        @jira = jira
        @github = github
        # nil = criar o adapter real. O caminho que NÃO escreve é dry_run: = 1
        # (rake tracking:preview e TRACER_DRY_RUN).
        @brag = brag
        @ledger = ledger
        @renderer = renderer
        @logger = logger
        @dry_run = dry_run
        @filtro = filtro
        @stdout = stdout
      end

      def call(day = Date.current)
        dias(day).sum { |d| reconstruir(d) }
      end

      private

      def dias(day)
        # Date puro (rake tracking:rebuild[21/10/2026]) não tem hora: reconstrói
        # só ele. Time.current reconstrói ontem até o meio-dia.
        # `day - 1` num Time subtrai SEGUNDO, não dia — daí o to_date.
        return [ day.to_date ] unless day.respond_to?(:hour)

        day.hour < MEIO_DIA ? [ day.to_date - 1, day.to_date ] : [ day.to_date ]
      end

      def reconstruir(day)
        report = BuildDayReport.new.call(day, jira: coletar_jira(day), github: coletar_github(day))
        blocos = report.vazio? ? [ @renderer.sem_atividade ] : @renderer.items(report)
        if @dry_run
          imprimir(day, report, blocos)
          return 0
        end
        # Dia vazio sem ledger: não cria seção vazia para um dia que nunca teve
        # atividade (só o header ficaria, poluindo o documento).
        return 0 if report.vazio? && ledger.day(day).nil?

        resultado = brag.rebuild(
          day,
          header: @renderer.header(day, report.epic_note),
          sentinel: @renderer.sentinel,
          blocos: blocos
        )
        @logger.info("[tracking] #{day.iso8601}: #{resultado}")
        resultado == :reescrito ? 1 : 0
      end

      # Adapter real, criado sob demanda (o dry_run não instancia Notion).
      def brag
        @brag ||= Repositories::BragDocumentRepository.new(ledger: ledger)
      end

      def ledger
        @ledger ||= Tracker::Brag::BlockLedger.new(page_id: ENV.fetch("TRACER_NOTION_BRAG_PAGE_ID"))
      end

      def coletar_jira(day)
        (@jira || Repositories::JiraDayRepository.new(filtro: @filtro)).dia(day)
      rescue Tracker::Error, KeyError => e
        @logger.error("[tracking] jira: #{e.class}: #{e.message}")
        Entities::JiraDay.new
      end

      def coletar_github(day)
        (@github || Repositories::GitHubDayRepository.new).dia(day)
      rescue Tracker::Error, KeyError => e
        @logger.error("[tracking] github: #{e.class}: #{e.message}")
        Entities::GitHubDay.new
      end

      # Preview em texto (usado pelo rake e pelo TRACER_DRY_RUN) — permite ler
      # o resultado real antes de qualquer escrita no Notion.
      def imprimir(day, report, blocos)
        @stdout.puts("== #{day.iso8601} ==")
        @stdout.puts("## #{@renderer.header(day, report.epic_note)[:heading_2][:rich_text].map { |t| t[:text][:content] }.join}")
        blocos.each do |bloco|
          tipo = bloco.fetch(:type).to_sym
          @stdout.puts("• #{texto_rich(bloco[tipo])}")
          Array(bloco[tipo][:children]).each { |filho| @stdout.puts("    - #{texto_rich(filho[filho.fetch(:type).to_sym])}") }
        end
      end

      def texto_rich(conteudo)
        Array(conteudo[:rich_text]).map { |t| t[:text][:content] }.join
      end
    end
  end
end
