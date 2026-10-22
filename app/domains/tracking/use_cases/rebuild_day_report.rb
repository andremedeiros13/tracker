# frozen_string_literal: true

module Tracking
  module UseCases
    # O ciclo do Tracking: coleta o dia (Jira + GitHub), agrega e manda o
    # BragDocument reescrever a seção. Coleta e agregação são as
    # responsabilidades daqui; header, sentinel, ledger e escrita são do
    # módulo da seção (Tracking::BragDocument).
    #
    # Reconstrução em vez de append: o dia só está completo quando acaba.
    # A coleta de cada fonte é resgatada em separado — Jira fora não pode
    # impedir o registro do GitHub (e vice-versa).
    #
    # Reconstrói hoje e, até o meio-dia, também ontem: o que foi mergeado
    # 00:30 ainda pertence ao dia anterior do ponto de vista de quem trabalhou.
    class RebuildDayReport
      MEIO_DIA = 12

      def initialize(jira: nil, github: nil, brag: nil,
                     logger: Rails.logger, dry_run: ENV["TRACER_DRY_RUN"] == "1",
                     filtro: ENV.fetch("TRACER_JIRA_FILTRO", "estreito"), stdout: $stdout,
                     renderer: Renderers::BragBlocks.new)
        @jira = jira
        @github = github
        # nil = criar o módulo real. O caminho que NÃO escreve é dry_run: = 1
        # (rake tracking:preview e TRACER_DRY_RUN).
        @brag = brag
        @logger = logger
        @dry_run = dry_run
        @filtro = filtro
        @stdout = stdout
        @renderer = renderer
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
        if @dry_run
          imprimir(day, report)
          return 0
        end

        resultado = brag.rewrite(day, report)
        @logger.info("[tracking] #{day.iso8601}: #{resultado}")
        resultado == :reescrito ? 1 : 0
      end

      # Módulo real, criado sob demanda (o dry_run não instancia Notion).
      def brag
        @brag ||= Tracking::BragDocument.new(renderer: @renderer)
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
      # o resultado real antes de qualquer escrita no Notion. Renderiza, não
      # introspecta blocks: o mesmo caminho que escreveria.
      def imprimir(day, report)
        blocos = report.vazio? ? [ @renderer.sem_atividade ] : @renderer.items(report)
        @stdout.puts("== #{day.iso8601} ==")
        @stdout.puts("## #{texto_rich(@renderer.header(day, report.epic_note)[:heading_2])}")
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
