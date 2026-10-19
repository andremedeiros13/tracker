# frozen_string_literal: true

require "net/http"
require "json"
require "base64"

module Tracker
  module Jira
    # Cliente HTTP puro do Jira Cloud (pesquisa #4 — sem gem de terceiro no
    # seam, mesmo padrão do Notion client). Auth Basic email:token; a
    # superfície usada: search JQL, changelog, field/search, myself.
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

      def myself
        request(:Get, "/rest/api/3/myself")
      end

      # Busca por JQL (v3) — paginado por nextPageToken.
      def search(jql)
        issues = []
        token = nil
        loop do
          query = { jql:, maxResults: 50, fields: "key,summary" }
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

      # Descoberta de custom fields — retorna o customfield_XXXXX usado no
      # changelog (fieldId). Usado pelo DiscoverReviewer.
      def discover_fields(query:)
        body = request(:Get, "/rest/api/3/field/search",
                       query: { type: "custom", query:, maxResults: 50 })
        body.fetch("values")
      end

      private

      def request(method, path, body: nil, query: nil)
        uri = URI("#{@site}#{path}")
        uri.query = URI.encode_www_form(query) if query&.any?
        req = Net::HTTP.const_get(method).new(uri)
        req["Authorization"] = "Basic #{Base64.strict_encode64("#{@email}:#{@token}")}"
        req["Accept"] = "application/json"
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body) if body

        resposta = com_retry_429 { Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) } }
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
