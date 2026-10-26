# frozen_string_literal: true

module Tracking
  module Entities
    # O dia inteiro, pronto para render: os itens já na ordem de exibição.
    DayReport = Data.define(:date, :work_items, :given_reviews, :commits) do
      def initialize(work_items: [], given_reviews: [], commits: [], **resto)
        super(work_items: Array(work_items),
              given_reviews: Array(given_reviews), commits: Array(commits), **resto)
      end

      def vazio? = work_items.empty? && given_reviews.empty? && commits.empty?
    end
  end
end
