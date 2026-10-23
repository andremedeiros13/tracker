# frozen_string_literal: true

module Tracking
  module UseCases
    # Agrega o dia: Jira (cards) + GitHub (PRs, reviews, commits) → DayReport.
    # Código puro, sem rede — é aqui que mora a regra de "o que conta como
    # entrega", e é o único lugar que muda quando o formato do Brag evoluir.
    #
    # A espinha é o card do Jira: um PR é ligado ao card pela key extraída do
    # título/corpo. PR sem card vira item próprio; card que eu movi mas não é
    # meu vira atividade (`:moved`), nunca entrega.
    #
    # O domínio recebe entities, não payloads: `mine` já vem resolvido pelos
    # adapters, que são quem conhece a identidade do engenheiro. Antes este
    # módulo carregava o `JIRA_ACCOUNT_ID` e comparava account ids que o
    # adapter já tinha usado — a mesma decisão em duas camadas.
    class BuildDayReport
      def initialize(status_chain: Parsers::StatusChain.new,
                     pull_request_body: Parsers::PullRequestBody.new)
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
          # Guardo a review, não a linha pronta: a copy do documento é do
          # renderer, e o estado de domínio (`:approved`) só vira texto lá.
          item.with(reviews_given: dadas)
        end
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
        atividades = jira.activities_for(card.key)
        movi = atividades.any? { |a| a.changelog? && a.mine && a.touches_status? && a.no_dia?(day) }
        comentei = atividades.any? { |a| a.comment? && a.mine }
        movi || comentei
      end

      def entradas_minhas(card, jira)
        jira.activities_for(card.key).select do |atividade|
          atividade.changelog? && atividade.mine && atividade.touches_status?
        end
      end

      def item_do_card(card, jira, day, por_key)
        pr = por_key[card.key]
        transicoes = transicoes_do_dia(card, jira, day)
        corpo = pr && @pull_request_body.call(pr.body)

        Entities::WorkItem.new(
          key: card.key,
          title: card.title,
          url: card.url,
          mine: card.mine,
          epic: card.epic,
          outcome: desfecho(card, pr),
          outcome_at: pr&.merged_at || ultima_atividade(card, jira, day),
          status_chain: @status_chain.call(transicoes),
          owner_name: card.mine ? nil : card.assignee_name,
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
      def desfecho(card, pr)
        return :moved unless card.mine
        return :merged if pr&.merged?
        return :done if card.done?

        :in_progress
      end

      def transicoes_do_dia(card, jira, day)
        entradas_minhas(card, jira)
          .select { |atividade| atividade.no_dia?(day) }
          .flat_map(&:status_pairs)
      end

      def ultima_atividade(card, jira, day)
        instantes = jira.activities_for(card.key).select { |a| a.no_dia?(day) }.map(&:at)
        instantes.max
      end

      def comentarios_meus(card, jira)
        jira.activities_for(card.key).count { |a| a.comment? && a.mine }
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
    end
  end
end
