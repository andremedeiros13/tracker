# frozen_string_literal: true

module Tracking
  module UseCases
    # Descobre o customfield "Reviewer" no Jira — imprime os fields
    # encontrados para o usuário copiar o id (customfield_XXXXX) pro .env
    # (JIRA_REVIEWER_FIELD_ID). JQL history não alcança custom fields, então
    # o rastreio do Reviewer usa esse id no changelog (pesquisa #4).
    class DiscoverReviewer
      def initialize(client: Tracker::Jira::Client.from_env, stdout: $stdout)
        @client = client
        @stdout = stdout
      end

      def call
        fields = @client.discover_fields(query: "Reviewer")
        return @stdout.puts("Nenhum custom field 'Reviewer' encontrado.") if fields.empty?

        @stdout.puts("Custom fields 'Reviewer' encontrados — copie o id pro .env:")
        fields.each do |field|
          @stdout.puts("  #{field.fetch('id')}  #{field.fetch('name')}  (#{field.dig('schema', 'type')})")
        end
        fields
      end
    end
  end
end
