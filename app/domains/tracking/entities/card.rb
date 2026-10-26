# frozen_string_literal: true

module Tracking
  module Entities
    # Um card do Jira que apareceu na janela, já normalizado pelo adapter.
    #
    # Existe porque o payload do Jira (`fields`, `assignee/displayName`,
    # `statusCategory.key`) vazava até o BuildDayReport: o domínio lia oito
    # chaves de um hash de strings. A entity é o contrato do seam — cada
    # adapter entrega entities (o do GitHub já entregava), e a forma do
    # payload morre onde é conhecida.
    #
    # `mine` é resolvido pelo adapter, que é quem sabe a identidade do
    # engenheiro. O domínio não compara account ids: pergunta se o card é meu.
    Card = Data.define(
      :key, :url, :title, :status, :status_category,
      :mine, :assignee_name, :reporter_name, :description, :id
    ) do
      def initialize(mine: false, description: nil, assignee_name: nil,
                     reporter_name: nil, **resto)
        super(mine: mine, description: description,
              assignee_name: assignee_name, reporter_name: reporter_name, **resto)
      end

      def done? = status_category == "done"
    end
  end
end
