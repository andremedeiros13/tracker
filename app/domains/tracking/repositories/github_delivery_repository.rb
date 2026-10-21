# frozen_string_literal: true

module Tracking
  module Repositories
    # Adapter GitHub do contexto Tracking: coleta PRs abertos, reviews feitos
    # e commits do engenheiro no dia. Reviews são filtradas client-side por
    # user.login (não existe endpoint "reviews por usuário" — pesquisa #4).
    class GitHubDeliveryRepository
      # Estados de review da API traduzidos para o Brag (é um registro em
      # português, não um espelho do payload do GitHub).
      ESTADOS_DE_REVIEW = {
        "APPROVED" => "Aprovado",
        "CHANGES_REQUESTED" => "Mudanças solicitadas",
        "COMMENTED" => "Comentou",
        "DISMISSED" => "Review dispensada"
      }.freeze

      # Qual review representa o PR quando o dia tem várias (comentar gera
      # várias "COMMENTED").
      PESO_DA_REVIEW = { "APPROVED" => 3, "CHANGES_REQUESTED" => 2, "COMMENTED" => 1, "DISMISSED" => 0 }.freeze

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
          detalhe = detalhe_do_pr(pr)
          detalhe ||= {}
          Entities::Delivery.new(
            source: :github,
            kind: :pr_aberto,
            title: pr.fetch("title"),
            detail: metricas_do_pr(detalhe),
            context: [ "#{repositorio_de(pr)}#{base_do_pr(detalhe)}".squeeze(" ") ].compact_blank.presence || [],
            url: pr.fetch("html_url"),
            occurred_at: Time.zone.parse(pr.fetch("created_at")),
            external_id: pr.fetch("id").to_s
          )
        end
      end

      # O detalhe do PR custa 1 request por PR do dia. Se falhar, o bullet
      # ainda sai — só sem as métricas.
      def detalhe_do_pr(pr)
        owner, repo = repositorio_do(pr)
        @client.pull_request(owner, repo, pr.fetch("number"))
      rescue Tracker::Error => e
        Rails.logger.warn("[tracking] github: detalhe do PR ##{pr['number']}: #{e.class}: #{e.message}")
        nil
      end

      def base_do_pr(detalhe)
        ref = detalhe.dig("base", "ref")
        ref ? " · base #{ref}" : ""
      end

      def reviews(nome, day)
        @client.search_prs("is:pr reviewed-by:#{nome} updated:>=#{day}").filter_map do |pr|
          review = review_do_dia(pr, nome, day)
          entrega_da_review(pr, review) if review
        end
      end

      # Uma review por PR: comentar gera várias reviews "COMMENTED" seguidas,
      # e no Brag isso virava 5 bullets idênticos. Fica a mais representativa
      # do dia (Aprovado > Mudanças > Comentou), cujo id é a chave do dedup.
      def review_do_dia(pr, nome, day)
        owner, repo = repositorio_do(pr)
        @client.pull_reviews(owner, repo, pr.fetch("number"))
               .select { |review| review_minha_no_dia?(review, nome, day) }
               .max_by { |review| PESO_DA_REVIEW.fetch(review["state"], 0) }
      end

      def review_minha_no_dia?(review, nome, day)
        review.dig("user", "login") == nome &&
          review.fetch("state") != "PENDING" &&
          no_dia?(review.fetch("submitted_at"), day)
      end

      def entrega_da_review(pr, review)
        Entities::Delivery.new(
          source: :github,
          kind: :review,
          title: pr.fetch("title"),
          detail: ESTADOS_DE_REVIEW.fetch(review.fetch("state"), review.fetch("state")),
          context: [ "PR ##{pr.fetch('number')} · #{repositorio_de(pr)}" ].compact_blank,
          url: pr.fetch("html_url"),
          occurred_at: Time.zone.parse(review.fetch("submitted_at")),
          external_id: review.fetch("id").to_s
        )
      end

      def commits(nome, day)
        @client.search_commits("author:#{nome} org:#{@org} committer-date:>=#{day}").map do |commit|
          Entities::Delivery.new(
            source: :github,
            kind: :commit,
            title: primeira_linha(commit),
            detail: nil,
            context: [ commit.dig("repository", "name") ].compact_blank,
            url: commit.fetch("html_url"),
            occurred_at: Time.zone.parse(commit.fetch("committer")["date"]),
            external_id: commit.fetch("sha")
          )
        end
      end

      # "17 arquivos, +1226/−55" — o peso da entrega, que o título sozinho não
      # conta. Vem do detalhe do PR (a busca não traz esses campos).
      def metricas_do_pr(detalhe)
        arquivos = detalhe["changed_files"]
        return unless arquivos

        partes = [ "#{arquivos} arquivo#{'s' unless arquivos == 1}" ]
        adicoes, remocoes = detalhe.values_at("additions", "deletions")
        partes << "+#{adicoes}/−#{remocoes}" if adicoes && remocoes
        partes.join(", ")
      end

      # "ResultadosDigitais/totvs-pay" a partir da repository_url.
      def repositorio_de(item)
        item["repository_url"].to_s[%r{/repos/([^/]+/[^/]+)\z}, 1]
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
