# frozen_string_literal: true

module Tracker
  module GitHub
    # Erro de domínio do GitHub — base própria, igual ao Notion.
    class Error < ::Tracker::Error; end

    class ApiError < Error
      def initialize(code, body) = super("GitHub API #{code}: #{body}")
    end
  end
end
