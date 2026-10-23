# frozen_string_literal: true

require "base64"

module Tracker
  module Jira
    # Cliente HTTP do Jira Cloud (pesquisa #4 — sem gem de terceiro no seam,
    # mesmo padrão do Notion client). Auth Basic email:token; a superfície
    # usada: search JQL, changelog (individual e em lote), field/search,
    # myself. Timeouts, retry de 429 e mapeamento de erro ficam no transporte
    # comum (Tracker::HTTP).
    class Client
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

      # Teto de issues por request do bulkfetch (a API responde 400 acima).
      LOTE_MAX_ISSUES = 1000

      # Changelog de vários issues em lote — 1 request por 1000 issues em vez
      # de um request por issue (era o N+1 que travava o ciclo por minutos).
      # Retorna { "<issueId>" => [histórias] }, onde cada história tem:
      #   - "created" em epoch ms (o endpoint individual devolve ISO 8601);
      #   - "author" como accountId (o individual devolve {accountId:}).
      # A normalização é do adapter (JiraDayRepository) — o domínio nunca vê
      # nem a diferença nem o formato.
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
        Tracker::HTTP.call(
          method:, url: "#{@site}#{path}", query:, body:,
          headers: {
            "Authorization" => "Basic #{Base64.strict_encode64("#{@email}:#{@token}")}",
            "Accept" => "application/json"
          },
          error: ApiError
        )
      end
    end
  end
end
