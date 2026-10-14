# frozen_string_literal: true

module Tracker
  module Jira
    # Erro de domínio do Jira (pesquisa #4) — base própria, igual ao Notion.
    class Error < ::Tracker::Error; end

    class ApiError < Error
      def initialize(code, body) = super("Jira API #{code}: #{body}")
    end
  end
end
