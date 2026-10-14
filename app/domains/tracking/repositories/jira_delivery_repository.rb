# frozen_string_literal: true

module Tracking
  module Repositories
    # Adapter Jira do contexto Tracking: coleta as entregas do engenheiro no
    # dia — cards movidos e mudanças no campo Reviewer, via changelog REST
    # API (JQL history não alcança custom fields — pesquisa #4).
    class JiraDeliveryRepository
      def initialize(client: Tracker::Jira::Client.from_env,
                     site: ENV.fetch("JIRA_SITE", "https://rdstation.atlassian.net"),
                     account_id: ENV.fetch("JIRA_ACCOUNT_ID"),
                     reviewer_field_id: ENV["JIRA_REVIEWER_FIELD_ID"])
        @client = client
        @site = site
        @account_id = account_id
        @reviewer_field_id = reviewer_field_id
      end

      # Entregas do dia: busca issues atualizadas na janela (JQL), baixa o
      # changelog de cada e filtra as entradas do engenheiro no dia alvo.
      def entregas_do_dia(day)
        @client.search(jql_da_janela).filter_map do |issue|
          entregas_do_issue(issue, day)
        end.flatten
      end

      private

      def jql_da_janela
        "updated >= -#{Tracker::Jira::Client::JANELA_JQL_DIAS}d ORDER BY updated DESC"
      end

      def entregas_do_issue(issue, day)
        entradas = @client.changelog(issue.fetch("key")).select do |entrada|
          entrada.dig("author", "accountId") == @account_id &&
            no_dia?(entrada.fetch("created"), day)
        end
        entradas.flat_map { |entrada| entregas_da_entrada(issue, entrada) }
      end

      def entregas_da_entrada(issue, entrada)
        itens = entrada.fetch("items").select { |item| item_relevante?(item) }
        itens.map do |item|
          Entities::Delivery.new(
            source: :jira,
            kind: item.fetch("fieldId") == "status" ? :card_movido : :reviewer,
            title: "#{item.fetch("field")}: #{issue.fetch('key')} — #{issue.fetch('fields').fetch('summary')}",
            url: url_do_card(issue.fetch("key")),
            occurred_at: Time.zone.parse(entrada.fetch("created")),
            external_id: "#{issue.fetch('key')}:#{entrada.fetch('id')}:#{item.fetch('fieldId')}"
          )
        end
      end

      # Status (card movido) e o campo Reviewer (customfield, quando
      # configurado) — o resto do changelog não é entrega.
      def item_relevante?(item)
        item.fetch("fieldId") == "status" ||
          (@reviewer_field_id && item.fetch("fieldId") == @reviewer_field_id)
      end

      def url_do_card(key)
        "#{URI.join(@site, "browse/#{key}")}"
      end

      def no_dia?(created, day)
        Time.zone.parse(created).to_date == day
      end
    end
  end
end
