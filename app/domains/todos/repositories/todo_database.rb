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
      STATUS_NOTIFICAVEIS = %i[pendente snoozed].map { |valor| NotionSchema.label_of(:status, valor) }.freeze

      def initialize(client: nil,
                     mapper: PropertyMapper.new,
                     database_id: nil)
        @client = client
        @mapper = mapper
        @database_id = database_id
      end

      # Tudo o que pode estar na fila agora (pendente ou snoozed), como entity.
      # SEM filtro de vencimento e SEM ordenação: quem decide o que já venceu e
      # em que ordem é a FilaDeAtencao, que é domínio. O filtro de status é
      # server-side (barato) e fica aqui.
      def notification_candidates
        client.query_database(database_id, filter: filtro_de_status)
              .map { |page| @mapper.from_page(page) }
      end

      # Cria uma row já no Status "Pendente". `origin` é o valor do domínio
      # (:manual, :via_jira, :via_transcricao) — o label do Notion vem do
      # NotionSchema, nunca literal.
      def create(title, origin: :manual)
        client.create_page(
          database_id:,
          properties: {
            NotionSchema.name_of(:name) => { title: [ { text: { content: title } } ] },
            NotionSchema.name_of(:status) => { status: { name: NotionSchema.label_of(:status, :pendente) } },
            NotionSchema.name_of(:origin) => { select: { name: NotionSchema.label_of(:origin, origin) } }
          }
        )
      end

      private

      # Resolvidos sob demanda: injetar um fake não deve exigir token nem id
      # no ENV. Antes eram defaults de parâmetro, avaliados mesmo quando o
      # chamador passava o seu — o seam valia metade.
      def client = @client ||= Tracker::Notion::Client.from_env

      def database_id = @database_id ||= ENV.fetch("TRACER_NOTION_DATABASE_ID")

      def filtro_de_status
        { or: STATUS_NOTIFICAVEIS.map { |nome| { property: NotionSchema.name_of(:status), status: { equals: nome } } } }
      end
    end
  end
end
