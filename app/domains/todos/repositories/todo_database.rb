# frozen_string_literal: true

module Todos
  module Repositories
    # O database "To-Dos" do Notion: a fila de atenção inteira (ADR 0001).
    #
    # Um módulo só porque a escrita e a leitura do MESMO schema não podem
    # divergir: antes o mapper derivava de NotionSchema e o
    # TodoCreationRepository (do OneOnOnes) montava as propriedades com strings
    # literais — renomear uma opção quebrava a escrita em runtime, não no boot,
    # e o validador de schema não cobria esse caminho.
    #
    # Interface: `notification_candidates` (o que o ciclo de notificação
    # considera agora) e `create` (uma row nova). Mapper e propriedades são
    # implementação.
    class TodoDatabase
      # Labels do Notion que o ciclo considera — derivados do schema (fonte
      # única), não literais: `pendente` (a notificar) e `snoozed` ("Em
      # andamento", porque ainda está na fila até ser concluída).
      STATUS_NOTIFICAVEIS = begin
        labels = NotionSchema::PROPERTIES.fetch("Status").fetch(:options).invert
        %i[pendente snoozed].map { |valor| labels.fetch(valor) }.freeze
      end

      def initialize(client: Tracker::Notion::Client.from_env,
                     mapper: PropertyMapper.new,
                     database_id: ENV.fetch("TRACER_NOTION_DATABASE_ID"))
        @client = client
        @mapper = mapper
        @database_id = database_id
      end

      # Pendências que o ciclo considera agora (pendente ou snoozed cujo
      # horário já venceu), ordenadas pelo que vence primeiro.
      def notification_candidates
        @client.query_database(filter: filtro_de_status)
               .map { |page| @mapper.from_page(page) }
               .select(&:lembrete_ativo?)
               .sort_by { |t| t.snoozed_until || t.created_at }
      end

      # Cria uma row já no Status "Pendente". `origin` é o valor do domínio
      # (:manual, :via_jira, :via_transcricao) — o label do Notion vem do
      # NotionSchema, nunca literal.
      def create(title, origin: :manual)
        @client.create_page(
          database_id: @database_id,
          properties: {
            "Name" => { title: [ { text: { content: title } } ] },
            "Status" => { status: { name: label_de("Status", :pendente) } },
            "Origem" => { select: { name: label_de("Origem", origin) } }
          }
        )
      end

      private

      def filtro_de_status
        { or: STATUS_NOTIFICAVEIS.map { |nome| { property: "Status", status: { equals: nome } } } }
      end

      # Label do Notion a partir do valor de domínio. Falha alto quando o valor
      # não existe no schema — o mesmo erro que o mapper dá na leitura.
      def label_de(propriedade, valor)
        opcoes = NotionSchema::PROPERTIES.fetch(propriedade).fetch(:options)
        opcoes.key(valor) || raise(KeyError, "opção #{valor.inspect} não existe em #{propriedade}")
      end
    end
  end
end
