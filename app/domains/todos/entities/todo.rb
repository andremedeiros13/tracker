# frozen_string_literal: true

module Todos
  module Entities
    # Entity imutável do domínio — espelho de uma page do Database "To-Dos".
    # Estado/origem são editados DIRETO no Notion (ADR 0001); o backend só lê.
    #
    # Estados: pendente -> snoozed (até X; a tarefa continua na fila, só para de
    # lembrar) -> concluída. Origens: manual, via_jira, via_transcricao.
    Todo = Data.define(
      :page_id, :title, :origin, :status,
      :snoozed_until, :created_at, :last_edited_time
    ) do
      # Snoozed SEM data é estado que o Notion permite (coluna "Em andamento"
      # sem "Snoozed até") e o schema não proíbe. Sem data não existe "até
      # quando silenciar", então lembra — é melhor avisar de novo do que sumir
      # com a tarefa. Antes o `<=` estourava NoMethodError em nil e derrubava
      # o ciclo de notificação inteiro enquanto a linha existisse.
      def lembrete_ativo?
        status == :pendente ||
          (status == :snoozed && (snoozed_until.nil? || snoozed_until <= Time.current))
      end
    end
  end
end
