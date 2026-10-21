# frozen_string_literal: true

module Tracking
  module Parsers
    # Comprime as transições de status do dia numa linha só:
    # [Prioritized→To Do, To Do→In Progress, In Progress→Review]
    # vira ["Prioritized → To Do → In Progress → Review"].
    #
    # Também decide o que NÃO é entrega: andar para trás no board
    # (Prioritized/To Do) é higiene, não trabalho entregue — o Brag não
    # registra "arrumei o board". Transições encadeadas com salto
    # (A→B e depois C→D sem ligação) viram duas linhas.
    class StatusChain
      # Colunas de entrada do board — mover para elas é planejamento.
      COLUNAS_DE_ENTRADA = [ "Backlog", "Prioritized", "To Do" ].freeze

      def call(transicoes)
        return [] if transicoes.empty?

        cadeias = []
        atual = nil
        transicoes.each do |de, para|
          if atual && atual.last == de
            atual << para
          else
            atual = [ de, para ]
            cadeias << atual
          end
        end

        cadeias.map { |cadeia| cadeia.join(" → ") }
               .reject { |cadeia| higiene?(cadeia) }
      end

      private

      # Toda a cadeia aconteceu dentro das colunas de entrada: o card não
      # avançou, só foi organizado.
      def higiene?(cadeia)
        cadeia.split(" → ").all? { |status| COLUNAS_DE_ENTRADA.include?(status) }
      end
    end
  end
end
