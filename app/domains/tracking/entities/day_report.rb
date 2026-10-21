# frozen_string_literal: true

module Tracking
  module Entities
    # O dia inteiro, pronto para render: os itens já na ordem de exibição e o
    # épico comum (quando TODOS os cards do dia são da mesma frente — aí ele
    # vai no header uma vez, em vez de repetir em cada item).
    DayReport = Data.define(:date, :epic_note, :work_items, :given_reviews, :commits) do
      def initialize(epic_note: nil, work_items: [], given_reviews: [], commits: [], **resto)
        super(epic_note: epic_note, work_items: Array(work_items),
              given_reviews: Array(given_reviews), commits: Array(commits), **resto)
      end

      def vazio? = work_items.empty? && given_reviews.empty? && commits.empty?
    end
  end
end
