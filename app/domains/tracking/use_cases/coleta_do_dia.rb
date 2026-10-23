# frozen_string_literal: true

module Tracking
  module UseCases
    # A coleta de um dia: Jira + GitHub, cada fonte resgatada em separado.
    #
    # Existe porque o resultado de uma coleta não é "um dia" — é um dia E a
    # informação de se ele está completo. Antes o `rescue` devolvia
    # `JiraDay.new` (dia vazio), o `BuildDayReport` agregava metade do dia, e
    # o rewrite comparava as assinaturas, via que mudaram e APAGAVA do Brag os
    # bullets do Jira. Um 500 transitório custava o registro do dia.
    #
    # O adapter já sabe que a chamada falhou — a informação existia e era
    # jogada fora. Aqui ela para no valor devolvido, e quem decide se escreve
    # é o chamador (`RebuildDayReport`), que é quem conhece a consequência.
    class ColetaDoDia
      # `completo?` é a pergunta que o chamador faz: alguma fonte falhou? Só
      # ele decide o que fazer com um dia incompleto (o RebuildDayReport não
      # reescreve o Brag).
      Resultado = Data.define(:jira, :github, :falhas) do
        def initialize(jira: nil, github: nil, falhas: [])
          super(jira: jira || Entities::JiraDay.new,
                github: github || Entities::GitHubDay.new,
                falhas: Array(falhas))
        end

        def completo? = falhas.empty?
      end

      def initialize(jira: nil, github: nil, logger: Rails.logger,
                     filtro: ENV.fetch("TRACER_JIRA_FILTRO", "estreito"))
        @jira = jira
        @github = github
        @logger = logger
        @filtro = filtro
      end

      def call(day)
        jira, falha_jira = coletar(:jira) { jira_repository.dia(day) }
        github, falha_github = coletar(:github) { github_repository.dia(day) }

        Resultado.new(jira:, github:, falhas: [ falha_jira, falha_github ].compact)
      end

      private

      # Uma fonte que falha não impede a outra: o resgate é por fonte e a
      # falha é registrada, não engolida em silêncio.
      def coletar(fonte)
        [ yield, nil ]
      rescue Tracker::Error, KeyError => e
        @logger.error("[tracking] #{fonte}: #{e.class}: #{e.message}")
        [ nil, fonte ]
      end

      def jira_repository
        @jira || Repositories::JiraDayRepository.new(filtro: @filtro)
      end

      def github_repository
        @github || Repositories::GitHubDayRepository.new
      end
    end
  end
end
