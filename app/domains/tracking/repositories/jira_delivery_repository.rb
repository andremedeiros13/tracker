# frozen_string_literal: true

module Tracking
  module Repositories
    # Adapter Jira do contexto Tracking: coleta as entregas do engenheiro no
    # dia — cards movidos e mudanças no campo Reviewer, via changelog REST
    # API (JQL history não alcança custom fields — pesquisa #4).
    class JiraDeliveryRepository
      # Tamanho máximo do resumo de contexto (primeira frase da descrição) —
      # o Brag é registro escaneável, não a descrição inteira do card.
      RESUME_MAX_CHARS = 180

      # Nome do épico no sub-bullet: só o suficiente para situar o card.
      EPICO_MAX_CHARS = 60

      # Campos trazidos na busca: os dois primeiros o adapter já usava; o resto
      # alimenta o contexto do bullet (tipo, épico, componente e a descrição,
      # de onde sai a primeira frase).
      CAMPOS_DO_CONTEXTO = "key,summary,issuetype,parent,components,description"

      def initialize(client: Tracker::Jira::Client.from_env,
                     site: ENV.fetch("JIRA_SITE", "https://rdstation.atlassian.net"),
                     account_id: ENV.fetch("JIRA_ACCOUNT_ID"),
                     reviewer_field_id: ENV["JIRA_REVIEWER_FIELD_ID"],
                     filtro: ENV.fetch("TRACER_JIRA_FILTRO", "largo"))
        @client = client
        @site = site
        @account_id = account_id
        @reviewer_field_id = reviewer_field_id
        @filtro = filtro
      end

      # Entregas do dia: busca issues atualizadas na janela (JQL), baixa o
      # changelog de todas em lote (bulkfetch) e filtra as entradas do
      # engenheiro no dia alvo.
      def entregas_do_dia(day)
        issues = @client.search(jql_da_janela, fields: CAMPOS_DO_CONTEXTO)
        return [] if issues.empty?

        changelogs = @client.changelog_em_lote(issues.map { |issue| issue.fetch("id") })
        issues.flat_map { |issue| entregas_do_issue(issue, changelogs.fetch(issue.fetch("id"), []), day) }
      end

      private

      # "largo" (default): tudo que mudou na janela — zero risco de perder
      # entrega, ~42s por ciclo. "estreito": só cards com a sua participação
      # — ~3s, mas o Jira NÃO aceita "CHANGED BY" em custom field, então o
      # Reviewer só entra se o card também tiver você como assignee/reporter
      # ou tiver tido status mexido por você (6/6 coberto nos 6 dias medidos
      # em 2026-10-21 — amostra pequena, não é garantia).
      def jql_da_janela
        base = "updated >= -#{Tracker::Jira::Client::JANELA_JQL_DIAS}d"
        return "#{base} ORDER BY updated DESC" unless @filtro == "estreito"

        "#{base} AND (#{criterios_de_participacao}) ORDER BY updated DESC"
      end

      # Condições que caracterizam "eu participei deste card". O Reviewer só
      # entra se o campo estiver configurado (o JQL exige o id numérico).
      def criterios_de_participacao
        criterios = [
          "status CHANGED BY currentUser()",
          "assignee = currentUser()",
          "reporter = currentUser()"
        ]
        criterios << "cf[#{id_numerico_do_reviewer}] = currentUser()" if id_numerico_do_reviewer
        criterios.join(" OR ")
      end

      # JQL não aceita o id cru do custom field: cf[customfield_10125] dá 400,
      # o formato válido é cf[10125].
      def id_numerico_do_reviewer
        @reviewer_field_id.to_s[/\d+\z/].presence
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
            title: "#{issue.fetch('key')} — #{resumo_do_issue(issue)}",
            detail: resumo_da_mudanca(item),
            context: contexto_do_issue(issue),
            url: url_do_card(issue.fetch("key")),
            occurred_at: criado_em(entrada),
            external_id: "#{issue.fetch('key')}:#{entrada.fetch('id')}:#{item.fetch('fieldId')}"
          )
        end
      end

      # O que mudou, em uma expressão: "Backlog → Review" ou o nome de quem
      # foi atribuído como reviewer. O changelog traz os dois como string
      # (o Reviewer chega como "[Fulano]").
      def resumo_da_mudanca(item)
        destino = item["toString"].to_s.delete_prefix("[").delete_suffix("]").presence
        origem = item["fromString"].to_s.delete_prefix("[").delete_suffix("]").presence
        return destino.to_s if origem.nil? || destino.nil?

        "#{origem} → #{destino}"
      end

      def resumo_do_issue(issue)
        issue.fetch("fields", {}).fetch("summary", "")
      end

      # Linhas de contexto do card: tipo + épico + componente, e a primeira
      # frase da descrição (que traz o "Contexto" escrito por quem abriu).
      def contexto_do_issue(issue)
        campos = issue.fetch("fields", {})
        linhas = []
        linhas << [ campos.dig("issuetype", "name"), nome_do_epico(campos),
                    Array(campos["components"]).map { |c| c["name"] }.join(", ").presence ]
                  .compact.reject(&:empty?).join(" · ").presence
        linhas << primeira_frase(campos["description"]).presence
        linhas.compact
      end

      # O épico costuma ter nome longo ("[Motor][Wave2] Pagamento com até 3
      # cartões - Fluxo de captura e gestão do ciclo de vida") e se repete em
      # toda entrega do dia — corta para o Brag continuar escaneável.
      def nome_do_epico(campos)
        resumir(campos.dig("parent", "fields", "summary"), EPICO_MAX_CHARS)
      end

      def resumir(texto, limite)
        texto = texto.to_s.squish
        return if texto.blank?

        texto.length > limite ? "#{texto[0, limite - 1].rstrip}…" : texto
      end

      # A descrição vem em ADF (árvore de nós); concatena o texto e corta na
      # primeira frase, limitado a RESUME_MAX_CHARS para não inflar o Brag.
      def primeira_frase(adf)
        texto = texto_do_adf(adf)
        return if texto.blank?

        frase = texto.split(/(?<=[.!?])\s+/).first.to_s
        frase.length > RESUME_MAX_CHARS ? "#{frase[0, RESUME_MAX_CHARS - 1]}…" : frase
      end

      # Concatena o texto do ADF separando por parágrafo: os blocos de topo
      # (ex.: o heading "Contexto") não podem colar na frase seguinte.
      def texto_do_adf(no)
        case no
        when Hash
          if no["type"] == "text"
            no["text"].to_s
          else
            Array(no["content"]).map { |filho| texto_do_adf(filho) }.reject(&:blank?).join(" ")
          end
        when Array
          no.map { |filho| texto_do_adf(filho) }.reject(&:blank?).join(" ")
        end.to_s.squish
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
