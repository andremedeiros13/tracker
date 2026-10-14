# frozen_string_literal: true

module Tracking
  module Repositories
    # Adapter GitHub do contexto Tracking: coleta PRs abertos, reviews feitos
    # e commits do engenheiro no dia. Reviews são filtradas client-side por
    # user.login (não existe endpoint "reviews por usuário" — pesquisa #4).
    class GitHubDeliveryRepository
      def initialize(client: Tracker::GitHub::Client.from_env,
                     org: ENV.fetch("GITHUB_ORG", "ResultadosDigitais"),
                     username: ENV["GITHUB_USERNAME"])
        @client = client
        @org = org
        @username = username
      end

      def entregas_do_dia(day)
        nome = username
        [ prs_abertos(nome, day), reviews(nome, day), commits(nome, day) ]
          .flatten.uniq { |entrega| [ entrega.kind, entrega.external_id ] }
      end

      private

      # Username resolvido preguiçosamente (chamada de rede só na 1ª coleta).
      def username
        @username ||= @client.authenticated_user.fetch("login")
      end

      def prs_abertos(nome, day)
        @client.search_prs("is:pr author:#{nome} created:>=#{day}").map do |pr|
          Entities::Delivery.new(
            source: :github,
            kind: :pr_aberto,
            title: "PR aberto: #{pr.fetch('title')}",
            url: pr.fetch("html_url"),
            occurred_at: Time.zone.parse(pr.fetch("created_at")),
            external_id: pr.fetch("id").to_s
          )
        end
      end

      def reviews(nome, day)
        @client.search_prs("is:pr reviewed-by:#{nome} updated:>=#{day}").flat_map do |pr|
          owner, repo = repositorio_do(pr)
          @client.pull_reviews(owner, repo, pr.fetch("number")).select do |review|
            review.dig("user", "login") == nome &&
              review.fetch("state") != "PENDING" &&
              no_dia?(review.fetch("submitted_at"), day)
          end.map do |review|
            Entities::Delivery.new(
              source: :github,
              kind: :review,
              title: "Review: #{pr.fetch('title')}",
              url: pr.fetch("html_url"),
              occurred_at: Time.zone.parse(review.fetch("submitted_at")),
              external_id: review.fetch("id").to_s
            )
          end
        end
      end

      def commits(nome, day)
        @client.search_commits("author:#{nome} org:#{@org} committer-date:>=#{day}").map do |commit|
          Entities::Delivery.new(
            source: :github,
            kind: :commit,
            title: "Commit: #{commit.fetch('repository')['name']} — #{primeira_linha(commit)}",
            url: commit.fetch("html_url"),
            occurred_at: Time.zone.parse(commit.fetch("committer")["date"]),
            external_id: commit.fetch("sha")
          )
        end
      end

      def repositorio_do(pr)
        pr.fetch("repository_url").match(%r{/repos/([^/]+)/([^/]+)$}).captures
      end

      def primeira_linha(commit)
        commit.fetch("commit").fetch("message").lines.first.to_s.strip
      end

      def no_dia?(timestamp, day)
        Time.zone.parse(timestamp).to_date == day
      end
    end
  end
end
