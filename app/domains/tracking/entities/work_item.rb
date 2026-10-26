# frozen_string_literal: true

module Tracking
  module Entities
    # Um item do Brag do dia. A unidade é o card (ou o PR, quando não há card)
    # — não o evento de API: um card movido 3 vezes é UM item com a cadeia de
    # status comprimida, não 3 bullets.
    #
    # `reviews_given` guarda as reviews (Entities::GivenReview), não linhas de
    # texto: a copy que aparece no documento é do renderer, dono do formato.
    # Guardar a linha pronta aqui fazia o estado de review ser traduzido no
    # domínio e no renderer.
    #
    # `outcome`:
    #   :merged      — PR mergeado hoje (o mais forte; vence status)
    #   :done        — statusCategory "done" no Jira
    #   :in_progress — qualquer outra coluna ativa
    #   :moved       — card que eu movi mas não é meu (aparece como atividade)
    #   :reviewed    — eu revisei o PR de outra pessoa
    #   :commented   — eu só comentei (sem mudança de status)
    WorkItem = Data.define(
      :key, :title, :url, :mine,
      :outcome, :outcome_at,
      :status_chain, :owner_name,
      :pull_requests, :reviews_received, :reviews_given,
      :comments_count, :problema, :solucao, :last_activity_at
    ) do
      def initialize(key: nil, mine: true, outcome_at: nil, status_chain: [],
                     owner_name: nil, pull_requests: [], reviews_received: [],
                     reviews_given: [], comments_count: 0, problema: nil,
                     solucao: nil, last_activity_at: nil, **resto)
        super(
          key: key, mine: mine, outcome_at: outcome_at,
          status_chain: Array(status_chain), owner_name: owner_name,
          pull_requests: Array(pull_requests), reviews_received: Array(reviews_received),
          reviews_given: Array(reviews_given), comments_count: comments_count,
          problema: problema, solucao: solucao, last_activity_at: last_activity_at, **resto
        )
      end

      def merged? = outcome == :merged
      def concluded? = %i[merged done].include?(outcome)
    end
  end
end
