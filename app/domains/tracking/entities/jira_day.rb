# frozen_string_literal: true

module Tracking
  module Entities
    # O dia de Jira: os cards que passaram por mim, o changelog deles e os
    # comentários meus do dia. Cru — quem transforma em WorkItem é o
    # BuildDayReport (regra de negócio pura, testável sem rede).
    JiraDay = Data.define(:cards, :changelogs, :comments) do
      def initialize(cards: [], changelogs: {}, comments: {}, **resto)
        super(cards: Array(cards), changelogs: changelogs, comments: comments, **resto)
      end
    end
  end
end
