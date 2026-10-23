# frozen_string_literal: true

module Todos
  # A fila de atenção: as pendências de agora, na ordem em que devem chegar ao
  # engenheiro — pelo que vence primeiro.
  #
  # Existe porque a ordenação morava no adapter do Notion (`TodoDatabase`) e
  # era reimplementada no fake do spec para o use case passar. A regra
  # "vence primeiro" não tinha nome nem lugar, e o domínio dependia de uma
  # ordem que não era dele. Aqui ela é um valor: código puro, testável sem
  # Notion, e o adapter só lê.
  #
  # Não ordena por data de criação absoluta: uma tarefa pendente "vence" na
  # criação (é a primeira vez que se olha para ela), mas uma snoozed que já
  # venceu voltou para a fila naquele instante — daí `proximo_lembrete`.
  module FilaDeAtencao
    module_function

    # Pendências de agora, ordenadas. `todos` é o que o adapter devolveu; o
    # filtro de status já foi feito lá (é server-side, barato), então aqui só
    # sobra "o lembrete está ativo?".
    def de(todos) = ordem(Array(todos).select(&:lembrete_ativo?))

    def ordem(todos) = todos.sort_by(&:proximo_lembrete)
  end
end
