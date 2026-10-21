# frozen_string_literal: true

module Tracking
  module Parsers
    # Extrai chaves de card do Jira de um texto livre (título/corpo de PR).
    # Nesta org a key vai no título ("CHEKOUT-2301 [Payments] …") e na primeira
    # linha do corpo (":ticket: [CHEKOUT-2301](url)"), então o casamento é o que
    # liga o PR ao card — sem isso o Brag lista o mesmo trabalho duas vezes.
    #
    # O regex exige 2+ dígitos finais para não casar "UTF-8", "HTTP-2" e afins.
    module TicketKeys
      PADRAO = /\b([A-Z][A-Z0-9]{1,9}-\d{2,})\b/

      module_function

      def call(*textos)
        textos.compact.flat_map { |texto| texto.to_s.scan(PADRAO).flatten }.uniq
      end
    end
  end
end
