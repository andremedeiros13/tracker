# frozen_string_literal: true

module Tracking
  module Repositories
    # Adapter Jira: traz os cards em que eu participei no dia + as atividades
    # (changelog normalizado + comentários) deles. Cru (Entities::JiraDay) — a
    # regra de "o que conta como entrega" é do BuildDayReport.
    #
    # O changelog do bulkfetch chega com duas anomalias em relação ao changelog
    # individual (created em epoch ms, author como accountId). Elas morrem aqui:
    # o domínio só vê Entities::Activity com autor e instante já resolvidos.
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
          activities: atividades_do_dia(cards, changelogs)
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

      # { "KEY" => [Activity, ...] } — changelog e comentários do dia já
      # unificados: o domínio pergunta "o que aconteceu neste card hoje",
      # não "de onde veio cada entrada".
      def atividades_do_dia(cards, changelogs)
        cards.each_with_object({}) do |card, acc|
          atividades = atividades_do_changelog(changelogs[card.fetch("id")]) +
                       atividades_dos_comentarios(card)
          acc[card.fetch("key")] = atividades.sort_by(&:at) unless atividades.empty?
        end
      end

      def atividades_do_changelog(entradas)
        Array(entradas).map do |entrada|
          Entities::Activity.new(
            kind: :changelog,
            author_id: autor_da(entrada),
            at: instante_de(entrada.fetch("created")),
            status_items: itens_de_status(entrada)
          )
        end
      end

      def atividades_dos_comentarios(card)
        Array(card.dig("fields", "comment", "comments")).map do |comentario|
          Entities::Activity.new(
            kind: :comment,
            author_id: comentario.dig("author", "accountId"),
            at: instante_de(comentario.fetch("created"))
          )
        end
      end

      # O bulkfetch devolve o author como accountId; o changelog individual
      # como {accountId:}. Aceitar os dois aqui é o que tira o shim do domínio.
      def autor_da(entrada)
        author = entrada["author"]
        author.respond_to?(:fetch) ? author["accountId"] : author
      end

      # idem para `created`: epoch ms no bulkfetch, ISO 8601 no individual.
      def instante_de(valor)
        texto = valor.to_s
        texto.match?(/\A\d+\z/) ? Time.zone.at(texto.to_i / 1000.0) : Time.zone.parse(texto)
      end

      def itens_de_status(entrada)
        Array(entrada.fetch("items")).filter_map do |item|
          next unless item["fieldId"] == "status"

          { from: limpar(item["fromString"]), to: limpar(item["toString"]) }
        end
      end

      def limpar(valor)
        valor.to_s.delete_prefix("[").delete_suffix("]").presence
      end

      def url_do_card(key)
        URI.join(@site, "browse/#{key}").to_s
      end
    end
  end
end
