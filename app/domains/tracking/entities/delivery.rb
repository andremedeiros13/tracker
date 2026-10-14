# frozen_string_literal: true

module Tracking
  module Entities
    # Entity imutável do domínio — uma entrega do dia, vinda do Jira ou do
    # GitHub. O external_id é o identificador estável da entrega (key do card,
    # SHA do commit, id do PR) — fonte do dedup contra o Brag document.
    #
    # Fontes: jira, github. Tipos: card_movido (status mudou), reviewer
    # (campo Reviewer mudou), pr_aberto, review, commit.
    Delivery = Data.define(
      :source, :kind, :title, :url, :occurred_at, :external_id
    )
  end
end
