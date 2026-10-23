# frozen_string_literal: true

module Todos
  module Repositories
    # Fonte única de verdade do Database "To-Dos" no Notion (ADR 0001: o
    # Database é criado manualmente com exatamente essas propriedades).
    #
    # As propriedades são indexadas por PAPEL do domínio, não pelo nome que
    # aparece no Notion: leitor e escritor perguntam por `:status`, e o nome
    # literal ("Status", "Snoozed até") existe uma vez só, aqui. Antes o nome
    # era redigitado no mapper e no writer — renomear uma propriedade passava
    # no boot e quebrava em runtime, que é justamente o que a validação de
    # schema deveria evitar.
    module NotionSchema
      DATABASE_NAME = "To-Dos"

      PROPERTIES = {
        name: { notion: "Name", type: "title" },
        status: { notion: "Status", type: "status", options: {
          "Pendente" => :pendente, "Em andamento" => :snoozed, "Concluída" => :concluida
        } },
        origin: { notion: "Origem", type: "select", options: {
          "Manual" => :manual, "Via Jira" => :via_jira, "Via Transcrição" => :via_transcricao
        } },
        snoozed: { notion: "Snoozed até", type: "date" }
      }.freeze

      module_function

      # Nome da propriedade no Notion (a chave do JSON da API).
      def name_of(role) = PROPERTIES.fetch(role).fetch(:notion)

      def options_of(role) = PROPERTIES.fetch(role)[:options] || {}

      # Label do Notion para um valor de domínio. Falha alto: uma opção que o
      # schema não declara é erro de programação, não de dados.
      def label_of(role, value)
        options_of(role).key(value) ||
          raise(KeyError, "opção #{value.inspect} não existe em #{name_of(role)}")
      end

      # Valor de domínio a partir do label do Notion. Falha alto no label
      # desconhecido — a leitura não inventa estado.
      def value_of(role, label) = options_of(role).fetch(label)

      # Como `value_of`, mas com default para quando o campo está vazio no
      # Notion (select nulo não é valor desconhecido: é ausência).
      def value_or(role, label, default) = options_of(role).fetch(label, default)
    end
  end
end
