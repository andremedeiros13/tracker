# frozen_string_literal: true

module Tracking
  module Repositories
    # Adapter GitHub: os PRs do engenheiro no dia, as reviews que ele deu e os
    # commits soltos. Cru (Entities::GitHubDay) — a agregação é do
    # BuildDayReport.
    #
    # Duas buscas de PR, unidas por número, porque uma só perde trabalho:
    #   created:>=dia  — PR aberto hoje
    #   merged:>=dia   — PR aberto antes e mergeado hoje (o caso do registro
    #                    "PR aberto" que nunca virava "mergeado")
    # `OR` dentro da mesma query retorna 0 (verificado em 2026-10-21).
    #
    # Os qualificadores de data do GitHub são UTC: buscamos de dia-1 e cortamos
    # client-side em Time.zone, senão um merge às 21:30 BRT cai no dia seguinte.
    class GitHubDayRepository
      # Estado do GitHub → estado de domínio. O adapter NÃO traduz para a copy
      # do documento: quem decide o que o leitor vê é o renderer, dono do
      # formato do Brag. Antes este mapa devolvia "Aprovado" e o renderer
      # mantinha outro mapa para os mesmos estados — dois vocabulários para um
      # conceito, em duas camadas.
      ESTADOS_DE_REVIEW = {
        "APPROVED" => :approved,
        "CHANGES_REQUESTED" => :changes_requested,
        "COMMENTED" => :commented,
        "DISMISSED" => :dismissed
      }.freeze

      PESO_DA_REVIEW = { "APPROVED" => 3, "CHANGES_REQUESTED" => 2, "COMMENTED" => 1, "DISMISSED" => 0 }.freeze

      def initialize(client: nil,
                     org: nil,
                     username: nil)
        @client = client
        @org = org
        @username = username
      end

      def dia(day)
        nome = username
        prs = meus_prs(nome, day)
        detalhes = prs.to_h { |pr| [ pr.fetch("number"), detalhe_do_pr(pr) ] }

        Entities::GitHubDay.new(
          pull_requests: prs.map { |pr| montar_pr(pr, detalhes[pr.fetch("number")], nome, day) },
          given_reviews: reviews_dadas(nome, day, prs),
          commits: commits(nome, day, prs))
      end

      private

      # Resolvidos sob demanda: o seam não pode exigir as variáveis do adapter
      # real quando o teste injeta um fake.
      def client = @client ||= Tracker::GitHub::Client.from_env

      def org = @org ||= ENV.fetch("GITHUB_ORG", "ResultadosDigitais")

      def username
        @username ||= ENV["GITHUB_USERNAME"] || client.authenticated_user.fetch("login")
      end

      # União das duas buscas, cortada pelo dia no fuso local.
      def meus_prs(nome, day)
        desde = day - 1
        consultas = [ "created:>=#{desde}", "merged:>=#{desde}" ]
        unicos = consultas.flat_map { |q| client.search_prs("is:pr author:#{nome} #{q}") }
                          .uniq { |pr| pr.fetch("number") }
        unicos
      end

      def detalhe_do_pr(pr)
        owner, repo = repositorio_do(pr)
        client.pull_request(owner, repo, pr.fetch("number"))
      rescue Tracker::Error => e
        Rails.logger.warn("[tracking] github: detalhe do PR ##{pr['number']}: #{e.class}: #{e.message}")
        {}
      end

      def montar_pr(pr, detalhe, nome, day)
        revisoes = reviews_do_pr(pr)
        proprias = revisoes.select { |r| r.dig("user", "login") == nome }
        aprovacoes = revisoes.filter_map do |r|
          next unless r["state"] == "APPROVED"
          next if bot?(r)

          r.dig("user", "login")
        end

        Entities::PullRequest.new(
          number: pr.fetch("number"),
          title: pr.fetch("title"),
          url: pr.fetch("html_url"),
          repo: repositorio_de(pr),
          body: pr["body"] || detalhe["body"],
          created_at: Time.zone.parse(pr.fetch("created_at")),
          merged_at: detalhe["merged_at"] && Time.zone.parse(detalhe["merged_at"]),
          commits: detalhe["commits"],
          changed_files: detalhe["changed_files"],
          additions: detalhe["additions"],
          deletions: detalhe["deletions"],
          my_comment_rounds: proprias.count { |r| r["state"] == "COMMENTED" },
          approvals: aprovacoes.uniq
        )
      end

      def reviews_do_pr(pr)
        owner, repo = repositorio_do(pr)
        client.pull_reviews(owner, repo, pr.fetch("number"))
      rescue Tracker::Error => e
        Rails.logger.warn("[tracking] github: reviews do PR ##{pr['number']}: #{e.class}: #{e.message}")
        []
      end

      def bot?(review)
        review.dig("user", "type") == "Bot" || review.dig("user", "login").to_s.end_with?("[bot]")
      end

      # Reviews que EU dei hoje, em PR que não é meu. Uma por PR (comentar gera
      # várias COMMENTED seguidas) — fica a mais representativa.
      def reviews_dadas(nome, day, meus)
        meus_numeros = meus.map { |pr| pr.fetch("number") }
        client.search_prs("is:pr reviewed-by:#{nome} updated:>=#{day - 1}").filter_map do |pr|
          next if meus_numeros.include?(pr.fetch("number"))

          review = review_do_dia(pr, nome, day)
          next unless review

          Entities::GivenReview.new(
            pull_request: Entities::PullRequest.new(
              number: pr.fetch("number"), title: pr.fetch("title"), url: pr.fetch("html_url"),
              repo: repositorio_de(pr), created_at: Time.zone.parse(pr.fetch("created_at"))
            ),
            state: ESTADOS_DE_REVIEW.fetch(review["state"]) { raise KeyError, "estado de review desconhecido: #{review["state"].inspect}" },
            submitted_at: Time.zone.parse(review.fetch("submitted_at"))
          )
        end
      end

      def review_do_dia(pr, nome, day)
        owner, repo = repositorio_do(pr)
        client.pull_reviews(owner, repo, pr.fetch("number"))
               .select { |r| r.dig("user", "login") == nome && r["state"] != "PENDING" && no_dia?(r["submitted_at"], day) }
               .max_by { |r| PESO_DA_REVIEW.fetch(r["state"], 0) }
      rescue Tracker::Error
        nil
      end

      # Commits fora de PR conhecido — o commit de PR já está contado no PR.
      #
      # O shape de /search/commits: `committer` na RAIZ é o usuário do GitHub
      # (id, login…), sem data; a data do commit está em `commit.committer.date`.
      # Ler a raiz estourava KeyError "date" e derrubava a coleta inteira do
      # GitHub — o dia saía sem os commits E sem os PRs.
      def commits(nome, day, prs)
        client.search_commits("author:#{nome} org:#{org} committer-date:>=#{day - 1}").filter_map do |commit|
          quando = Time.zone.parse(commit.dig("commit", "committer", "date").to_s)
          next unless quando

          next unless quando.to_date == day

          Entities::Commit.new(
            sha: commit.fetch("sha"),
            message: commit.dig("commit", "message").to_s.lines.first.to_s.strip,
            url: commit.fetch("html_url"),
            repo: commit.dig("repository", "name"),
            committed_at: quando
          )
        end
      end

      def repositorio_de(item)
        item["repository_url"].to_s[%r{/repos/([^/]+/[^/]+)\z}, 1]
      end

      def repositorio_do(pr)
        pr.fetch("repository_url").match(%r{/repos/([^/]+)/([^/]+)$}).captures
      end

      def no_dia?(timestamp, day)
        Time.zone.parse(timestamp).to_date == day
      end
    end
  end
end
