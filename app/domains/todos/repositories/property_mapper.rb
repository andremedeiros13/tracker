# frozen_string_literal: true

module Todos
  module Repositories
    # Mapper Notion page JSON → Todos::Entities::Todo.
    # Falha rápido em propriedade/opção desconhecida (o boot valida o schema
    # contra NotionSchema antes — ADR 0001).
    #
    # Os nomes das propriedades vêm do schema por papel: nenhum label literal
    # aqui (ver NotionSchema).
    class PropertyMapper
      def from_page(page)
        props = page.fetch("properties")
        Entities::Todo.new(
          page_id: page.fetch("id"),
          title: props.fetch(NotionSchema.name_of(:name)).fetch("title").map { |t| t.fetch("plain_text") }.join,
          status: NotionSchema.value_of(:status, valor(props, :status, "status", "name")),
          # Origem vazia (select null) = tarefa criada direto no Notion → manual.
          origin: NotionSchema.value_or(:origin, valor(props, :origin, "select", "name"), :manual),
          snoozed_until: parse_data(valor(props, :snoozed, "date", "start")),
          created_at: Time.zone.parse(page.fetch("created_time")),
          last_edited_time: Time.zone.parse(page.fetch("last_edited_time"))
        )
      end

      private

      # Lê o campo interno da propriedade (status.name, select.name, date.start)
      # sem repetir o nome do Notion no chamador.
      def valor(props, role, tipo, campo)
        props.dig(NotionSchema.name_of(role), tipo, campo)
      end

      # Date com hora vem ISO-8601 UTC; date-only ("2026-10-09") vira início
      # do dia. "Snoozed até" deve ter hora para snooze preciso.
      def parse_data(valor)
        return nil if valor.nil?

        valor.length == 10 ? Time.zone.parse("#{valor} 00:00") : Time.zone.parse(valor)
      end
    end
  end
end
