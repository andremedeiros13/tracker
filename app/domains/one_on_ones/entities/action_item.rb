# frozen_string_literal: true

module OneOnOnes
  module Entities
    # Entity imutável do domínio — um action item do checkbox "Próximas
    # etapas" (`- [ ] [Nome] Título: descrição`). `mine` é calculado na
    # importação (matching parcial do nome com o usuário) — só os meus viram
    # To-Dos (origem via_transcricao); os outros ficam no histórico.
    ActionItem = Data.define(
      :meeting, :description, :owner, :mine
    ) do
      def mine? = mine
    end
  end
end
