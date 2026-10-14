# frozen_string_literal: true

module Tracking
  module UseCases
    # O ciclo do Tracking: coleta as entregas do dia (Jira + GitHub) e
    # appenda no Brag document só as que ainda não estão (dedup incremental —
    # nada fica pra trás, trabalho depois das 18:00 entra também).
    #
    # Erro de coleta (credencial ausente/expirada, API fora) é resgatado e
    # logado — nunca derruba o ciclo do scheduler.
    class CollectTodaysDeliveries
      def initialize(jira: nil, github: nil,
                     brag: Repositories::BragDocumentRepository.new,
                     logger: Rails.logger)
        @jira = jira
        @github = github
        @brag = brag
        @logger = logger
      end

      def call(day = Date.current)
        entregas = coletar(:jira, day) + coletar(:github, day)
        return if entregas.empty?

        novas = rejeitar_ja_registradas(entregas, day)
        @brag.append(day, novas)
        novas.size
      end

      private

      # Jira só roda com credenciais configuradas (issue #10) — sem elas, a
      # coleta é pulada sem erro. GitHub resolve o token do ENV ou do gh CLI.
      def coletar(fonte, day)
        case fonte
        when :jira
          return [] unless jira_configurado?

          (@jira || Repositories::JiraDeliveryRepository.new).entregas_do_dia(day)
        when :github
          (@github || Repositories::GitHubDeliveryRepository.new).entregas_do_dia(day)
        end
      rescue Tracker::Error, Tracker::Notion::Error, KeyError => e
        @logger.error("[tracking] #{fonte}: #{e.class}: #{e.message}")
        []
      end

      def jira_configurado?
        @jira || (Tracker::Jira::Client.configurado? && ENV["JIRA_ACCOUNT_ID"].present?)
      end

      # Dedup contra o Brag document: entrega já registrada tem o external_id
      # embutido no bullet (contrato do formato — ver BragDocumentRepository).
      def rejeitar_ja_registradas(entregas, day)
        registrados = @brag.entregas_existentes(day).map { |e| e.fetch(:external_id) }
        entregas.reject { |entrega| registrados.include?(entrega.external_id) }
      end
    end
  end
end
