# frozen_string_literal: true

module Tracking
  module UseCases
    # O ciclo do Tracking: coleta o dia (Jira + GitHub), agrega e manda o
    # BragDocument reescrever a seção. Coleta é da ColetaDoDia; agregação é do
    # BuildDayReport; header, sentinel, ledger e escrita são do módulo da
    # seção (Tracking::BragDocument).
    #
    # Reconstrução em vez de append: o dia só está completo quando acaba.
    # A coleta de cada fonte é resgatada em separado — Jira fora não pode
    # impedir o registro do GitHub (e vice-versa).
    #
    # RECONSTRÓI SOBRE DIA COMPLETO: um dia com falha de coleta NÃO é
    # reescrito, porque reescrever apagaria do Brag a metade que veio do
    # adaptador que falhou. O dia fica como estava e o próximo ciclo (ou a
    # varredura larga) tenta de novo. Antes, a falha virava dia vazio e o
    # rewrite apagava a metade do Jira — perda de dado silenciosa.
    #
    # Reconstrói hoje e, até o meio-dia, também ontem: o que foi mergeado
    # 00:30 ainda pertence ao dia anterior do ponto de vista de quem trabalhou.
    class RebuildDayReport
      MEIO_DIA = 12

      def initialize(jira: nil, github: nil, brag: nil,
                     coleta: nil,
                     logger: Rails.logger, dry_run: ENV["TRACER_DRY_RUN"] == "1",
                     filtro: ENV.fetch("TRACER_JIRA_FILTRO", "estreito"), stdout: $stdout)
        @jira = jira
        @github = github
        # nil = criar o módulo real. O caminho que NÃO escreve é dry_run: = 1
        # (rake tracking:preview e TRACER_DRY_RUN).
        @brag = brag
        @coleta = coleta
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
        coleta = coletar(day)
        unless coleta.completo?
          @logger.warn("[tracking] #{day.iso8601}: coleta incompleta (#{coleta.falhas.join(', ')}) — Brag não reescrito")
          return 0
        end

        report = BuildDayReport.new.call(day, jira: coleta.jira, github: coleta.github)
        # O preview em texto é do módulo do Brag: ele é o dono da copy, então
        # as duas formas (blocos e texto) saem do mesmo lugar. Antes este use
        # case mantinha um segundo traversal que precisava concordar com o
        # renderer sobre header, ordem e dia vazio.
        return preview(day, report) if @dry_run

        resultado = brag.rewrite(day, report)
        @logger.info("[tracking] #{day.iso8601}: #{resultado}")
        resultado == :reescrito ? 1 : 0
      end

      def coletar(day)
        (@coleta || ColetaDoDia.new(jira: @jira, github: @github, logger: @logger, filtro: @filtro)).call(day)
      end

      # Módulo real, criado sob demanda (o dry_run não instancia Notion).
      def brag
        @brag ||= Tracking::BragDocument.new
      end

      def preview(day, report)
        @stdout.puts(brag.preview(day, report))
        0
      end
    end
  end
end
