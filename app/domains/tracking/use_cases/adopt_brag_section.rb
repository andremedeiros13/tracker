# frozen_string_literal: true

module Tracking
  module UseCases
    # Migração única: marca a seção de um dia que já existe no Brag (escrita
    # no formato antigo, um bullet por evento) como gerada pelo Tracker, para
    # que o rewrite possa apagá-la e reescrever no formato novo.
    #
    # O trabalho é do módulo da seção (Tracking::BragDocument#adopt) — aqui só
    # fica o ponto de entrada do rake. Só roda por rake, nunca pelo scheduler:
    # é destrutiva. Antes de tocar no Notion, o módulo grava o texto atual em
    # storage/tracking/brag_<dia>.bak (o conteúdo antigo não é recuperável pelo
    # ledger depois).
    class AdoptBragSection
      def initialize(brag: nil, logger: Rails.logger, stdout: $stdout)
        @brag = brag || Tracking::BragDocument.new(stdout:, logger:)
      end

      def call(day) = @brag.adopt(day)
    end
  end
end
