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
                     filtro: ENV.fetch("TRACER_JIRA_FILTRO", "estreito"), stdout: $stdout)
        @jira = jira
        @github = github
        # nil = criar o módulo real. O caminho que NÃO escreve é dry_run: = 1
        # (rake tracking:preview e TRACER_DRY_RUN).
        @brag = brag
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
        # O preview em texto é do módulo do Brag: ele é o dono da copy, então
        # as duas formas (blocos e texto) saem do mesmo lugar. Antes este use
        # case mantinha um segundo traversal que precisava concordar com o
        # renderer sobre header, ordem e dia vazio.
        return preview(day, report) if @dry_run

        resultado = brag.rewrite(day, report)
        @logger.info("[tracking] #{day.iso8601}: #{resultado}")
        resultado == :reescrito ? 1 : 0
      end

      # Módulo real, criado sob demanda (o dry_run não instancia Notion).
      def brag
        @brag ||= Tracking::BragDocument.new
      end

      def preview(day, report)
        @stdout.puts(brag.preview(day, report))
        0
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
    end
  end
end
