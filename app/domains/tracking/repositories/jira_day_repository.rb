# frozen_string_literal: true

module Tracking
  module Repositories
    # Adapter Jira: traz os cards em que eu participei no dia + o changelog
    # deles + os comentários meus do dia. Cru (Entities::JiraDay) — a regra de
    # "o que conta como entrega" é do BuildDayReport.
    #
    # Filtro `estreito` (default): só cards com a minha participação, ~0,5 s.
    # Filtro `largo`: tudo que mudou na janela — 3.400 issues e ~60 s por ciclo,
    # só usado pela varredura diária de segurança (JQL não aceita
    # "comment CHANGED BY", então comentário meu em card de outro só aparece no
    # largo, quando o card também tem status/assignee/reporter meus).
    class JiraDayRepository
      # Campos que o Brag precisa. `comment` já vem no mesmo request (0,47 s,
      # 80 KB para 6 cards medidos em 2026-10-21).
      CAMPOS = "key,summary,status,assignee,reporter,parent,issuetype,components,description,comment"

      def initialize(client: Tracker::Jira::Client.from_env,
                     site: ENV.fetch("JIRA_SITE", "https://rdstation.atlassian.net"),
                     account_id: ENV.fetch("JIRA_ACCOUNT_ID"),
                     reviewer_field_id: ENV["JIRA_REVIEWER_FIELD_ID"],
                     filtro: ENV.fetch("TRACER_JIRA_FILTRO", "estreito"))
        @client = client
        @site = site
        @account_id = account_id
        @reviewer_field_id = reviewer_field_id
        @filtro = filtro
      end

      def dia(day)
        cards = @client.search(jql_da_janela, fields: CAMPOS)
        return Entities::JiraDay.new if cards.empty?

        changelogs = @client.changelog_em_lote(cards.map { |card| card.fetch("id") })
        Entities::JiraDay.new(
          cards: cards.map { |card| normalizar(card) },
          changelogs: changelogs,
          comments: comentarios_do_dia(cards, day)
        )
      end

      private

      def jql_da_janela
        base = "updated >= -#{Tracker::Jira::Client::JANELA_JQL_DIAS}d"
        return "#{base} ORDER BY updated DESC" unless @filtro == "estreito"

        "#{base} AND (#{criterios_de_participacao}) ORDER BY updated DESC"
      end

      def criterios_de_participacao
        criterios = [ "status CHANGED BY currentUser()", "assignee = currentUser()", "reporter = currentUser()" ]
        criterios << "cf[#{id_numerico_do_reviewer}] = currentUser()" if id_numerico_do_reviewer
        criterios.join(" OR ")
      end

      # JQL não aceita o id cru do custom field: cf[customfield_10125] dá 400.
      def id_numerico_do_reviewer
        @reviewer_field_id.to_s[/\d+\z/].presence
      end

      # Campos que o BuildDayReport usa, já achatados (o adapter normaliza o
      # payload do Jira; o domínio não conhece "fields"/"assignee/displayName").
      def normalizar(card)
        campos = card.fetch("fields", {})
        {
          "key" => card.fetch("key"),
          "url" => url_do_card(card.fetch("key")),
          "title" => campos["summary"].to_s,
          "status" => campos.dig("status", "name").to_s,
          "status_category" => campos.dig("status", "statusCategory", "key").to_s,
          "assignee" => campos.dig("assignee", "displayName"),
          "assignee_id" => campos.dig("assignee", "accountId"),
          "reporter" => campos.dig("reporter", "displayName"),
          "epic" => campos.dig("parent", "fields", "summary"),
          "description" => campos["description"],
          "id" => card.fetch("id")
        }
      end

      # { "KEY" => [ { author_id:, created_at: }, ... ] } — só os comentários
      # do dia, com o autor resolvido (o BuildDayReport conta os meus).
      def comentarios_do_dia(cards, day)
        cards.each_with_object({}) do |card, acc|
          comentarios = Array(card.dig("fields", "comment", "comments")).filter_map do |comentario|
            quando = Time.zone.parse(comentario.fetch("created").to_s)
            next unless quando.to_date == day

            { author_id: comentario.dig("author", "accountId"), created_at: quando }
          end
          acc[card.fetch("key")] = comentarios unless comentarios.empty?
        end
      end

      def url_do_card(key)
        URI.join(@site, "browse/#{key}").to_s
      end
    end
  end
end
