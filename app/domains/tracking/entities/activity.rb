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
    # `mine` e não `author_id`: o domínio só precisa saber se a atividade é do
    # engenheiro, e quem sabe a identidade dele é o adapter. Guardar o autor
    # cru obrigava o domínio a receber o mesmo account id que o adapter já
    # tinha resolvido — duas camadas decidindo a mesma coisa.
    #
    # `status_items` são só os itens de status do changelog — `from`/`to` vêm
    # nil quando o Jira não informa o lado (card criado já numa coluna). Esse
    # nil é semântica do Jira, não detalhe de transporte, então fica na entity:
    # `touches_status?` diz que o card teve movimento, `status_pairs` só as
    # transições completas (o que vira a cadeia do Brag).
    # `kind` separa comentário de entrada de changelog: sem isso, um changelog
    # que só mudou a descrição seria contado como "eu comentei".
    Activity = Data.define(:kind, :mine, :at, :status_items) do
      def initialize(kind:, at:, mine: false, status_items: [], **resto)
        super(kind:, mine:, at:, status_items: Array(status_items), **resto)
      end

      def comment? = kind == :comment
      def changelog? = kind == :changelog

      def touches_status? = status_items.any?

      def status_pairs = status_items.filter_map { |item| [ item[:from], item[:to] ] if item[:from] && item[:to] }

      def no_dia?(day) = at.to_date == day
    end
  end
end
