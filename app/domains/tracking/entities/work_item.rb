# frozen_string_literal: true

module Tracking
  module Entities
    # Um item do Brag do dia. A unidade é o card (ou o PR, quando não há card)
    # — não o evento de API: um card movido 3 vezes é UM item com a cadeia de
    # status comprimida, não 3 bullets.
    #
    # `outcome`:
    #   :merged      — PR mergeado hoje (o mais forte; vence status)
    #   :done        — statusCategory "done" no Jira
    #   :in_progress — qualquer outra coluna ativa
    #   :moved       — card que eu movi mas não é meu (aparece como atividade)
    #   :reviewed    — eu revisei o PR de outra pessoa
    #   :commented   — eu só comentei (sem mudança de status)
    WorkItem = Data.define(
      :key, :title, :url, :mine, :epic,
      :outcome, :outcome_at,
      :status_chain, :owner_name,
      :pull_requests, :reviews_received, :reviews_given,
      :comments_count, :problema, :solucao, :last_activity_at
    ) do
      def initialize(key: nil, mine: true, epic: nil, outcome_at: nil, status_chain: [],
                     owner_name: nil, pull_requests: [], reviews_received: [],
                     reviews_given: [], comments_count: 0, problema: nil,
                     solucao: nil, last_activity_at: nil, **resto)
        super(
          key: key, mine: mine, epic: epic, outcome_at: outcome_at,
          status_chain: Array(status_chain), owner_name: owner_name,
          pull_requests: Array(pull_requests), reviews_received: Array(reviews_received),
          reviews_given: Array(reviews_given), comments_count: comments_count,
          problema: problema, solucao: solucao, last_activity_at: last_activity_at, **resto
        )
      end

      def merged? = outcome == :merged
      def concluded? = %i[merged done].include?(outcome)

      # "#2301" — a referência curta que abre o bullet.
      def referencia = key ? "##{key.split('-').last}" : "PR ##{pull_requests.first&.number}"
    end
  end
end
