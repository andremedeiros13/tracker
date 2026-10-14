# frozen_string_literal: true

module OneOnOnes
  module Entities
    # Entity imutável do domínio — uma reunião extraída da transcrição do
    # Meet. Múltiplas reuniões por arquivo (delimitadas por data + título);
    # o resumo é o que vira a page 1-on-1 (ADR 0001).
    Meeting = Data.define(
      :date, :title, :participants, :summary, :source_file
    )
  end
end
