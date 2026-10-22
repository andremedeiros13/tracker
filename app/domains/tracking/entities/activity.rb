# frozen_string_literal: true

module Tracking
  module Entities
    # Uma entrada de changelog do Jira, já normalizada pelo adapter.
    #
    # Existe porque o bulkfetch (o request em lote que evita o N+1) devolve
    # `created` em epoch ms e `author` como accountId, enquanto o changelog
    # individual devolve ISO 8601 e `{accountId: ...}`. Antes essa diferença
    # vazava até o BuildDayReport, que carregava dois shims defensivos; aqui ela
    # morre no adapter.
    #
    # `status_items` são só os itens de status do changelog — `from`/`to` vêm
    # nil quando o Jira não informa o lado (card criado já numa coluna). Esse
    # nil é semântica do Jira, não detalhe de transporte, então fica na entity:
    # `touches_status?` diz que o card teve movimento, `status_pairs` só as
    # transições completas (o que vira a cadeia do Brag).
    # `kind` separa comentário de entrada de changelog: sem isso, um changelog
    # que só mudou a descrição seria contado como "eu comentei".
    Activity = Data.define(:kind, :author_id, :at, :status_items) do
      def initialize(kind:, at:, author_id: nil, status_items: [], **resto)
        super(kind:, author_id:, at:, status_items: Array(status_items), **resto)
      end

      def comment? = kind == :comment
      def changelog? = kind == :changelog

      def mine?(account_id) = author_id == account_id

      def touches_status? = status_items.any?

      def status_pairs = status_items.filter_map { |item| [ item[:from], item[:to] ] if item[:from] && item[:to] }

      def no_dia?(day) = at.to_date == day
    end
  end
end
