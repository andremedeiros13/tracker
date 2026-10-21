# frozen_string_literal: true

require "net/http"
require "json"
require "base64"

module Tracker
  module Jira
    # Cliente HTTP puro do Jira Cloud (pesquisa #4 — sem gem de terceiro no
    # seam, mesmo padrão do Notion client). Auth Basic email:token; a
    # superfície usada: search JQL, changelog (individual e em lote),
    # field/search, myself.
    class Client
      # Sem timeout, um socket pendurado trava o ciclo inteiro do daemon (o
      # tracking ficou 199s num ciclo que normalmente leva 8s). 10s para abrir
      # e 30s para ler cobre com folga o payload do bulkfetch do Jira.
      TIMEOUT_ABERTURA = 10
      TIMEOUT_LEITURA = 30
      # Janela de busca JQL em dias (issues atualizadas recentemente — o
      # filtro do dia alvo acontece client-side no changelog).
      JANELA_JQL_DIAS = 2

      def initialize(email:, token:, site:)
        @email = email
        @token = token
        @site = site
      end

      def self.from_env
        new(email: ENV.fetch("JIRA_EMAIL"),
            token: ENV.fetch("JIRA_API_TOKEN"),
            site: ENV.fetch("JIRA_SITE", "https://rdstation.atlassian.net"))
      end

      def self.configurado?
        ENV["JIRA_EMAIL"] && ENV["JIRA_API_TOKEN"]
      end

      def myself
        request(:Get, "/rest/api/3/myself")
      end

      # Tamanho de página da busca. A API aceita 5000: uma janela de 2 dias
      # (~3.500 issues) vem em 1 request de ~1,4s, contra 70 requests e ~34s
      # com o default de 50.
      BUSCA_MAX_ISSUES = 5000

      # Busca por JQL (v3) — paginado por nextPageToken. `fields` escolhe o que
      # vem de cada issue: sem ele o Jira devolve só id/self.
      def search(jql, fields: "key,summary")
        issues = []
        token = nil
        loop do
          query = { jql:, maxResults: BUSCA_MAX_ISSUES, fields: }
          query[:nextPageToken] = token if token
          body = request(:Get, "/rest/api/3/search/jql", query:)
          issues.concat(body.fetch("issues"))
          break if body.fetch("isLast", true)

          token = body.fetch("nextPageToken")
        end
        issues
      end

      # Changelog paginado do issue (isLast/nextPage, maxResults 100).
      def changelog(issue_id_or_key)
        entradas = []
        token = nil
        loop do
          query = { maxResults: 100 }
          query[:nextPage] = token if token
          body = request(:Get, "/rest/api/3/issue/#{issue_id_or_key}/changelog", query:)
          entradas.concat(body.fetch("values"))
          break if body.fetch("isLast", true)

          token = body.fetch("nextPage")
        end
        entradas
      end

      # Teto de issues por request do bulkfetch (a API responde 400 acima).
      LOTE_MAX_ISSUES = 1000

      # Changelog de vários issues em lote — 1 request por 1000 issues em vez
      # de um request por issue (era o N+1 que travava o ciclo por minutos).
      # Retorna { "<issueId>" => [histórias] }, com o MESMO shape do changelog
      # individual, exceto:
      #   - "created" vem em epoch ms (no individual vem em ISO 8601);
      #   - "author" vem como accountId (no individual vem como {accountId:}).
      # A normalização é do adapter (JiraDeliveryRepository).
      #
      # maxResults é um orçamento de histórias por página; o resto vem por
      # nextPageToken. 5000 mede ~10,6s por lote de 1000 issues, contra 16,7s
      # com 1000 (12 páginas → 3).
      def changelog_em_lote(issue_ids, max_results: 5000)
        por_issue = Hash.new { |hash, chave| hash[chave] = [] }
        issue_ids.uniq.each_slice(LOTE_MAX_ISSUES) do |lote|
          buscar_historias_do_lote(lote, por_issue, max_results)
        end
        por_issue
      end

      # Descoberta de custom fields — retorna o customfield_XXXXX usado no
      # changelog (fieldId). Usado pelo DiscoverReviewer.
      def discover_fields(query:)
        body = request(:Get, "/rest/api/3/field/search",
                       query: { type: "custom", query:, maxResults: 50 })
        body.fetch("values")
      end

      private

      # Pagina um lote (até LOTE_MAX_ISSUES) até esgotar nextPageToken.
      def buscar_historias_do_lote(lote, por_issue, max_results)
        token = nil
        loop do
          body = { issueIdsOrKeys: lote, maxResults: max_results }
          body[:nextPageToken] = token if token
          resposta = request(:Post, "/rest/api/3/changelog/bulkfetch", body:)
          resposta.fetch("issueChangeLogs").each do |log|
            por_issue[log.fetch("issueId")].concat(log.fetch("changeHistories", []))
          end
          token = resposta["nextPageToken"]
          break unless token
        end
      end

      def request(method, path, body: nil, query: nil)
        uri = URI("#{@site}#{path}")
        uri.query = URI.encode_www_form(query) if query&.any?
        req = Net::HTTP.const_get(method).new(uri)
        req["Authorization"] = "Basic #{Base64.strict_encode64("#{@email}:#{@token}")}"
        req["Accept"] = "application/json"
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body) if body

        resposta = com_retry_429 { Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT_ABERTURA, read_timeout: TIMEOUT_LEITURA) { |http| http.request(req) } }
        raise ApiError.new(resposta.code, resposta.body) unless resposta.is_a?(Net::HTTPSuccess)

        JSON.parse(resposta.body)
      end

      # Honra Retry-After no 429 (rate limit do Jira Cloud).
      def com_retry_429(max_tentativas: 2)
        tentativas = 0
        loop do
          resposta = yield
          return resposta unless resposta.code == "429"
          raise ApiError.new(resposta.code, resposta.body) if tentativas >= max_tentativas

          sleep(resposta["Retry-After"]&.to_f || 1.0)
          tentativas += 1
        end
      end
    end
  end
end
