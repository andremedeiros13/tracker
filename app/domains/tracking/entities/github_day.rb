# frozen_string_literal: true

module Tracking
  module Entities
    # O dia de GitHub: os PRs do engenheiro, as reviews que ele deu (em PR de
    # terceiros — Entities::GivenReview) e os commits soltos. `pull_requests`
    # já cobre o PR criado em outro dia e mergeado neste — a busca por created
    # não o pegaria.
    GitHubDay = Data.define(:pull_requests, :given_reviews, :commits) do
      def initialize(pull_requests: [], given_reviews: [], commits: [], **resto)
        super(pull_requests: Array(pull_requests), given_reviews: Array(given_reviews),
              commits: Array(commits), **resto)
      end
    end
  end
end
