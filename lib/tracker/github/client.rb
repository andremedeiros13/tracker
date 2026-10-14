# frozen_string_literal: true

require "net/http"
require "json"

module Tracker
  module GitHub
    # Cliente HTTP puro da API do GitHub (pesquisa #4 — sem gem de terceiro
    # no seam). Token do ENV ou do gh CLI já autenticado; a superfície usada:
    # busca de PRs/commits, reviews de PR, user autenticado.
    class Client
      BASE = "https://api.github.com"

      def initialize(token:)
        @token = token
      end

      # Token do ENV; fallback: gh CLI (scopes repo + read:org cobrem o
      # rastreio — pesquisa #4). Falha cedo se nenhum dos dois existir.
      def self.from_env
        token = ENV["GITHUB_TOKEN"] || token_do_gh
        raise Error, "GitHub não configurado: GITHUB_TOKEN ausente e gh CLI sem auth" unless token

        new(token: token)
      end

      def authenticated_user
        request(:Get, "/user")
      end

      # Busca de PRs (search/issues com type:pr) — paginado por page.
      def search_prs(query)
        request(:Get, "/search/issues",
                query: { q: "#{query} type:pr", per_page: 50 }).fetch("items")
      end

      # Busca de commits — paginado por page (só a branch default é pesquisada).
      def search_commits(query)
        request(:Get, "/search/commits",
                query: { q: query, per_page: 50 }).fetch("items")
      end

      # Reviews de um PR, em ordem cronológica — não existe endpoint "reviews
      # por usuário"; o filtro por user.login acontece client-side (repository).
      def pull_reviews(owner, repo, pull_number)
        request(:Get, "/repos/#{owner}/#{repo}/pulls/#{pull_number}/reviews",
                query: { per_page: 100 })
      end

      private

      def self.token_do_gh
        # gh auth token imprime o token no stdout.
        `gh auth token`.strip.presence
      rescue StandardError
        nil
      end

      def request(method, path, body: nil, query: nil)
        uri = URI("#{BASE}#{path}")
        uri.query = URI.encode_www_form(query) if query&.any?
        req = Net::HTTP.const_get(method).new(uri)
        req["Authorization"] = "Bearer #{@token}"
        req["Accept"] = "application/vnd.github+json"
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body) if body

        resposta = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
        raise ApiError.new(resposta.code, resposta.body) unless resposta.is_a?(Net::HTTPSuccess)

        JSON.parse(resposta.body)
      end
    end
  end
end
