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

        # Uma pergunta só por card ("o que eu fiz nele hoje"), respondida uma
        # vez e reusada por participação, transições, instante e comentários.
        # Antes eram quatro predicados consultando as atividades de novo, e
        # os quatro precisavam concordar sobre a mesma regra.
        atividades = jira.cards.index_with { |card| AtividadeDoDia.new(card, jira, day) }

        cards = jira.cards.select { |card| atividades[card].participou? }
        itens = cards.map { |card| item_do_card(card, atividades[card], por_key) }
                     .reject { |item| sem_conteudo?(item) }
        itens.concat(prs_sem_card(prs, itens))
        # Review minha em PR de card que está no dia fica NA LINHA do card, não
        # na seção do fim: "mexi no #2332 e aprovei o PR" é um fato só.
        itens, avulsas = anexar_reviews_aos_cards(itens, github.given_reviews)

        Entities::DayReport.new(
          date: day,
          work_items: ordenar(itens),
          given_reviews: avulsas,
          commits: github.commits
        )
      end

      private

      # A atividade do engenheiro num card, no dia. Objeto interno (não é
      # interface do use case): a pergunta "eu participei deste card?" e as
      # três métricas que a acompanham saem da mesma leitura das atividades.
      AtividadeDoDia = Data.define(:card, :jira, :day) do
        # O card entra no dia se eu movi o status ou comentei. O comentário
        # não exige `no_dia?`: a janela do Jira já é curta e o comentário é meu
        # de qualquer forma (é o que o filtro largo da varredura pega).
        def participou? = moveu? || comentou?

        # Transições de status do dia, na ordem — o que vira a cadeia.
        def transicoes = minhas.select { |a| a.no_dia?(day) }.flat_map(&:status_pairs)

        def ultima_atividade
          todas.select { |a| a.no_dia?(day) }.map(&:at).max
        end

        def comentarios = todas.count { |a| a.comment? && a.mine }

        private

        def todas = jira.activities_for(card.key)

        def minhas = todas.select { |a| a.changelog? && a.mine && a.touches_status? }

        def moveu? = minhas.any? { |a| a.no_dia?(day) }

        def comentou? = todas.any? { |a| a.comment? && a.mine }
      end

      # Anexa as reviews dadas ao WorkItem do card correspondente (casando pela
      # key do PR revisado). Devolve [itens, reviews que ficaram sem card].
      #
      # Indexa as reviews pela key do PR revisado, como os PRs já eram
      # indexados: antes o casamento era `select` dentro de `map`, rodando o
      # regex de TicketKeys a cada par item × review e controlado por uma
      # lista `usadas` — O(n²) com bookkeeping.
      def anexar_reviews_aos_cards(itens, reviews)
        return [ itens, reviews ] if reviews.empty?

        por_key = reviews.group_by { |review| key_do_pr(review.pull_request) }

        atualizados = itens.map do |item|
          # Item sem card (PR avulso) não casa com nada — e `delete(nil)`
          # engoliria as reviews de PR também sem key.
          next item if item.key.nil?

          dadas = por_key.delete(item.key)
          next item if dadas.nil?

          # Guardo a review, não a linha pronta: a copy do documento é do
          # renderer, e o estado de domínio (`:approved`) só vira texto lá.
          item.with(reviews_given: dadas)
        end
        # O que sobrou no índice são as reviews de PR cujo card não entrou no
        # dia — vão para a seção do fim.
        [ atualizados, por_key.values.flatten ]
      end

      # Card em que só houve higiene de board (cadeia descartada) e nada mais:
      # não é entrega e não tem o que registrar.
      def sem_conteudo?(item)
        item.status_chain.empty? && item.pull_requests.empty? && item.comments_count.zero?
      end

      def item_do_card(card, atividade, por_key)
        pr = por_key[card.key]
        corpo = pr && @pull_request_body.call(pr.body)

        Entities::WorkItem.new(
          key: card.key,
          title: card.title,
          url: card.url,
          mine: card.mine,
          outcome: desfecho(card, pr),
          outcome_at: pr&.merged_at || atividade.ultima_atividade,
          status_chain: @status_chain.call(atividade.transicoes),
          owner_name: card.mine ? nil : card.assignee_name,
          pull_requests: [ pr ].compact,
          reviews_received: pr&.approvals.to_a,
          reviews_given: [],
          comments_count: atividade.comentarios,
          problema: corpo&.fetch(:problema),
          solucao: corpo&.fetch(:solucao),
          last_activity_at: atividade.ultima_atividade
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

      def key_do_pr(pr) = Parsers::TicketKeys.call(pr.title, pr.body).first

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
