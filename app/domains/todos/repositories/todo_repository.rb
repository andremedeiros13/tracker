# frozen_string_literal: true

module Todos
  module Repositories
    # Adapter Notion do contexto Todos (ADR 0001): lê pages do Database
    # "To-Dos". O Notion é a fonte da verdade — o estado é editado lá, o
    # backend só lê (polling incremental no ciclo, last_edited_time).
    class TodoRepository
      def initialize(client: Tracker::Notion::Client.from_env, mapper: PropertyMapper.new)
        @client = client
        @mapper = mapper
      end

      # Pendências que o ciclo de notificação considera agora (pendente ou
      # snoozed cujo horário já venceu), ordenadas pelo que vence primeiro.
      def notificaveis_agora
        @client.query_database(
          filter: { or: [ "Pendente", "Em andamento" ].map { |nome| { property: "Status", status: { equals: nome } } } }
        ).map { |page| @mapper.from_page(page) }
         .select(&:lembrete_ativo?)
         .sort_by { |t| t.snoozed_until || t.created_at }
      end
    end
  end
end
