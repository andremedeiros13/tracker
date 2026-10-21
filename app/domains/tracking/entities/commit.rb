# frozen_string_literal: true

module Tracking
  module Entities
    # Um commit solto do dia (fora de PR conhecido) — a cauda do Brag.
    Commit = Data.define(:sha, :message, :url, :repo, :committed_at) do
      def short_sha = sha[0, 7]
    end
  end
end
