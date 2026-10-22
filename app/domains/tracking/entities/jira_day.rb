# frozen_string_literal: true

module Tracking
  module Entities
    # O dia de Jira: os cards que passaram por mim e as atividades deles
    # (changelog + comentários, já normalizados pelo adapter). Cru — quem
    # transforma em WorkItem é o BuildDayReport (regra de negócio pura,
    # testável sem rede).
    #
    # `activities` é { "<KEY>" => [Entities::Activity, ...] }, ordenado por
    # instante. O domínio não vê epoch ms, formato de author nem o shape cru do
    # bulkfetch — só autor, instante e itens de status.
    JiraDay = Data.define(:cards, :activities) do
      def initialize(cards: [], activities: {}, **resto)
        super(cards: Array(cards), activities: activities, **resto)
      end

      def activities_for(key) = Array(activities[key])
    end
  end
end
