# frozen_string_literal: true

module Tracking
  module Entities
    # Entity imutável do domínio — uma entrega do dia, vinda do Jira ou do
    # GitHub. O external_id é o identificador estável da entrega (key do card,
    # SHA do commit, id do PR) — fonte do dedup contra o Brag document.
    #
    # Fontes: jira, github. Tipos: card_movido (status mudou), reviewer
    # (campo Reviewer mudou), pr_aberto, review, commit.
    #
    # `detail` é o resumo de contexto vindo da fonte (transição de status,
    # quem foi atribuído, estado da review, tamanho do PR) — vai em negrito no
    # bullet. `context` são as linhas explicativas que vão como sub-bullets
    # ("História · épico", primeira frase da descrição do card).
    Delivery = Data.define(
      :source, :kind, :title, :url, :occurred_at, :external_id,
      :detail, :context
    ) do
      def initialize(detail: nil, context: [], **resto)
        super(detail: detail, context: Array(context), **resto)
      end
    end
  end
end
