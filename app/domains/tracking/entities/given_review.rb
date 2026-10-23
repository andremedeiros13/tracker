# frozen_string_literal: true

module Tracking
  module Entities
    # Uma review que EU dei no dia, em PR de outra pessoa.
    #
    # `state` é o estado de domínio (`:approved`, `:changes_requested`,
    # `:commented`, `:dismissed`) — não a copy do documento. A tradução para o
    # que o leitor vê é do renderer, que é o dono do formato do Brag; antes o
    # adapter devolvia "Aprovado" e o renderer mantinha outro mapa para os
    # mesmos estados.
    GivenReview = Data.define(:pull_request, :state, :submitted_at)
  end
end
