# frozen_string_literal: true

module OneOnOnes
  module Repositories
    # Cria rows no database "To-Dos" do Notion (ADR 0001 — o To-Dos é o
    # único database). Origem "Via Transcrição"; usa o schema fonte única de
    # verdade do contexto Todos.
    class TodoCreationRepository
      def initialize(client: Tracker::Notion::Client.from_env,
                     database_id: ENV.fetch("TRACER_NOTION_DATABASE_ID"))
        @client = client
        @database_id = database_id
      end

      def create_todo(title, origin: "Via Transcrição")
        @client.create_page(
          database_id: @database_id,
          properties: {
            "Name" => { title: [ { text: { content: title } } ] },
            "Status" => { status: { name: "Pendente" } },
            "Origem" => { select: { name: origin } }
          }
        )
      end
    end
  end
end
