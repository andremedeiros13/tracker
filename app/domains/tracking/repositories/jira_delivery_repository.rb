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
      # changelog de todas em lote (bulkfetch) e filtra as entradas do
      # engenheiro no dia alvo.
      def entregas_do_dia(day)
        issues = @client.search(jql_da_janela)
        return [] if issues.empty?

        changelogs = @client.changelog_em_lote(issues.map { |issue| issue.fetch("id") })
        issues.flat_map { |issue| entregas_do_issue(issue, changelogs.fetch(issue.fetch("id"), []), day) }
      end

      private

      def jql_da_janela
        "updated >= -#{Tracker::Jira::Client::JANELA_JQL_DIAS}d ORDER BY updated DESC"
      end

      def entregas_do_issue(issue, entradas, day)
        entradas.select do |entrada|
          autor(entrada) == @account_id && no_dia?(criado_em(entrada), day)
        end.flat_map { |entrada| entregas_da_entrada(issue, entrada) }
      end

      # O bulkfetch devolve "author" como accountId; o changelog individual,
      # como {accountId:} — aceita os dois.
      def autor(entrada)
        entrada["author"].respond_to?(:fetch) ? entrada["author"]["accountId"] : entrada["author"]
      end

      # O bulkfetch devolve "created" em epoch ms; o individual, em ISO 8601.
      def criado_em(entrada)
        created = entrada.fetch("created").to_s
        created.match?(/\A\d+\z/) ? Time.zone.at(created.to_i / 1000.0) : Time.zone.parse(created)
      end

      def entregas_da_entrada(issue, entrada)
        itens = entrada.fetch("items").select { |item| item_relevante?(item) }
        itens.map do |item|
          Entities::Delivery.new(
            source: :jira,
            kind: item.fetch("fieldId") == "status" ? :card_movido : :reviewer,
            title: "#{item.fetch("field")}: #{issue.fetch('key')} — #{issue.fetch('fields').fetch('summary')}",
            url: url_do_card(issue.fetch("key")),
            occurred_at: criado_em(entrada),
            external_id: "#{issue.fetch('key')}:#{entrada.fetch('id')}:#{item.fetch('fieldId')}"
          )
        end
      end

      # Status (card movido) e o campo Reviewer (customfield, quando
      # configurado) — o resto do changelog não é entrega.
      # Item sem fieldId existe: o campo Rank vem só com "field"/"fieldtype"
      # — por isso [] e não fetch.
      def item_relevante?(item)
        item["fieldId"] == "status" ||
          (@reviewer_field_id && item["fieldId"] == @reviewer_field_id)
      end

      def url_do_card(key)
        "#{URI.join(@site, "browse/#{key}")}"
      end

      def no_dia?(created, day)
        created.to_date == day
      end
    end
  end
end
