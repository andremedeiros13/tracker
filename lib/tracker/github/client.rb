# frozen_string_literal: true

module Tracker
  module GitHub
    # Cliente HTTP da API do GitHub (pesquisa #4 — sem gem de terceiro no
    # seam). Token do ENV ou do gh CLI já autenticado; a superfície usada:
    # busca de PRs/commits, reviews de PR, user autenticado. Timeouts, retry de
    # 429 e mapeamento de erro ficam no transporte comum (Tracker::HTTP).
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

      # Detalhe do PR. A busca (/search/issues) não devolve changed_files,
      # additions nem base — só este endpoint devolve, então o adapter faz um
      # request por PR do dia (poucos).
      def pull_request(owner, repo, pull_number)
        request(:Get, "/repos/#{owner}/#{repo}/pulls/#{pull_number}")
      end

      private

      def self.token_do_gh
        # gh auth token imprime o token no stdout.
        `gh auth token`.strip.presence
      rescue StandardError
        nil
      end

      def request(method, path, body: nil, query: nil)
        Tracker::HTTP.call(
          method:, url: "#{BASE}#{path}", query:, body:,
          headers: {
            "Authorization" => "Bearer #{@token}",
            "Accept" => "application/vnd.github+json"
          },
          error: ApiError
        )
      end
    end
  end
end
