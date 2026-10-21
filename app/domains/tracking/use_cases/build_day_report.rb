# frozen_string_literal: true

module Tracking
  module UseCases
    # Agrega o dia: Jira (cards) + GitHub (PRs, reviews, commits) → DayReport.
    # Código puro, sem rede — é aqui que mora a regra de "o que conta como
    # entrega", e é o único lugar que muda quando o formato do Brag evoluir.
    #
    # A espinha é o card do Jira: um PR é ligado ao card pela key extraída do
    # título/corpo. PR sem card vira item próprio; card movido por mim mas não
    # meu vira atividade (`:moved`), nunca entrega.
    class BuildDayReport
      def initialize(account_id: ENV.fetch("JIRA_ACCOUNT_ID"),
                     status_chain: Parsers::StatusChain.new,
                     pull_request_body: Parsers::PullRequestBody.new)
        @account_id = account_id
        @status_chain = status_chain
        @pull_request_body = pull_request_body
      end

      def call(day, jira: Entities::JiraDay.new, github: Entities::GitHubDay.new)
        prs = github.pull_requests
        por_key = prs.index_by { |pr| key_do_pr(pr) }

        cards = jira.cards.select { |card| participou?(card, jira, day) }
        itens = cards.map { |card| item_do_card(card, jira, day, por_key) }
                     .reject { |item| sem_conteudo?(item) }
        itens.concat(prs_sem_card(prs, itens))
        # Review minha em PR de card que está no dia fica NA LINHA do card, não
        # na seção do fim: "mexi no #2332 e aprovei o PR" é um fato só.
        itens, avulsas = anexar_reviews_aos_cards(itens, github.given_reviews)
        # O épico só vai no header se todos os ITENS do dia são dele — um card
        # de outra frente descartado acima não estraga o resumo.
        epic_note = epico_comum(itens)

        Entities::DayReport.new(
          date: day,
          epic_note: epic_note,
          work_items: ordenar(itens),
          given_reviews: avulsas,
          commits: github.commits
        )
      end

      private

      # Anexa as reviews dadas ao WorkItem do card correspondente (casando pela
      # key do PR revisado). Devolve [itens, reviews que ficaram sem card].
      def anexar_reviews_aos_cards(itens, reviews)
        return [ itens, reviews ] if reviews.empty?

        usadas = []
        atualizados = itens.map do |item|
          dadas = reviews.reject { |r| usadas.include?(r) }.select { |review| mesma_key?(item, review) }
          next item if dadas.empty?

          usadas.concat(dadas)
          item.with(reviews_given: dadas.map { |review| "#{review.state.downcase} o PR ##{review.pull_request.number}" })        end
        [ atualizados, reviews - usadas ]
      end

      def mesma_key?(item, review)
        return false if item.key.nil?

        Parsers::TicketKeys.call(review.pull_request.title, review.pull_request.body).include?(item.key)
      end

      # Card em que só houve higiene de board (cadeia descartada) e nada mais:
      # não é entrega e não tem o que registrar.
      def sem_conteudo?(item)
        item.status_chain.empty? && item.pull_requests.empty? && item.comments_count.zero?
      end

      # O card entra no dia se eu movi o status, comentei, ou ele é meu e teve
      # atividade hoje.
      def participou?(card, jira, day)
        movi = entradas_minhas(card, jira).any? { |entrada| no_dia?(entrada, day) }
        comentei = Array(jira.comments[card["key"]]).any? { |c| c[:author_id] == @account_id }
        movi || comentei
      end

      def entradas_minhas(card, jira)
        Array(jira.changelogs[card["id"]]).select do |entrada|
          autor(entrada) == @account_id && entrada.fetch("items").any? { |i| i["fieldId"] == "status" }
        end
      end

      def autor(entrada)
        entrada["author"].respond_to?(:fetch) ? entrada["author"]["accountId"] : entrada["author"]
      end

      def item_do_card(card, jira, day, por_key)
        pr = por_key[card["key"]]
        mine = card["assignee_id"] == @account_id
        transicoes = transicoes_do_dia(card, jira, day)
        corpo = pr && @pull_request_body.call(pr.body)

        Entities::WorkItem.new(
          key: card["key"],
          title: card["title"],
          url: card["url"],
          mine: mine,
          epic: card["epic"],
          outcome: desfecho(card, pr, mine),
          outcome_at: pr&.merged_at || ultima_atividade(card, jira, day),
          status_chain: @status_chain.call(transicoes),
          owner_name: mine ? nil : card["assignee"],
          pull_requests: [ pr ].compact,
          reviews_received: pr&.approvals.to_a,
          reviews_given: [],
          comments_count: comentarios_meus(card, jira),
          problema: corpo&.fetch(:problema),
          solucao: corpo&.fetch(:solucao),
          last_activity_at: ultima_atividade(card, jira, day)
        )
      end

      # O desfecho do card de outra pessoa NUNCA é :done/:merged — o quê
      # aconteceu com o card não é o que EU fiz. Fica :moved (eu o movi) e a
      # linha diz de quem é.
      def desfecho(card, pr, mine)
        return :moved unless mine
        return :merged if pr&.merged?
        return :done if card["status_category"] == "done"

        :in_progress
      end

      def transicoes_do_dia(card, jira, day)
        entradas_minhas(card, jira)
          .select { |entrada| no_dia?(entrada, day) }
          .flat_map { |entrada| entrada.fetch("items").select { |i| i["fieldId"] == "status" } }
          .filter_map { |item| [ limpar(item["fromString"]), limpar(item["toString"]) ] if item["fromString"] && item["toString"] }
      end

      def limpar(valor)
        valor.to_s.delete_prefix("[").delete_suffix("]").presence
      end

      def ultima_atividade(card, jira, day)
        entradas = entradas_minhas(card, jira).map { |e| criado_em(e) } +
                  Array(jira.comments[card["key"]]).map { |c| c[:created_at] }
        entradas.map(&:to_date).count(day).positive? ? entradas.max : nil
      end

      def comentarios_meus(card, jira)
        Array(jira.comments[card["key"]]).count { |c| c[:author_id] == @account_id }
      end

      # PR cujo card não entrou no dia (ou sem card): item próprio, para o
      # trabalho não sumir do registro.
      def prs_sem_card(prs, itens)
        keys = itens.filter_map(&:key)
        prs.reject { |pr| keys.include?(key_do_pr(pr)) }.map do |pr|
          corpo = @pull_request_body.call(pr.body)
          Entities::WorkItem.new(
            title: pr.title, url: pr.url, mine: true,
            outcome: pr.merged? ? :merged : :in_progress,
            outcome_at: pr.merged_at || pr.created_at,
            pull_requests: [ pr ],
            reviews_received: pr.approvals,
            problema: corpo[:problema], solucao: corpo[:solucao],
            last_activity_at: pr.merged_at || pr.created_at
          )
        end
      end

      def key_do_pr(pr)
        Parsers::TicketKeys.call(pr.title, pr.body).first
      end

      # Só quando todos os itens do dia têm o mesmo épico — aí ele vai uma vez
      # no header, em vez de repetir em cada item.
      def epico_comum(itens)
        return if itens.empty?

        epicos = itens.filter_map(&:epic).map { |e| e.to_s.squish }.reject(&:blank?).uniq
        epicos.size == 1 ? epicos.first : nil
      end

      # Concluídos (merge desc) → em andamento (atividade desc) → cards de
      # outros. Ordem estável para o dia não pular a cada ciclo.
      def ordenar(itens)
        grupos = [ %i[merged done], %i[in_progress commented], %i[moved reviewed] ]
        grupos.flat_map do |grupo|
          itens.select { |i| grupo.include?(i.outcome) }
               .sort_by { |i| -(i.outcome_at || i.last_activity_at || Time.zone.at(0)).to_i }
        end
      end

      def no_dia?(entrada, day)
        criado_em(entrada).to_date == day
      end

      def criado_em(entrada)
        created = entrada.fetch("created").to_s
        created.match?(/\A\d+\z/) ? Time.zone.at(created.to_i / 1000.0) : Time.zone.parse(created)
      end
    end
  end
end
