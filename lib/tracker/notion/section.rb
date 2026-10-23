# frozen_string_literal: true

module Tracker
  module Notion
    # Uma seção de um dia numa page que guarda registros por dia (Brag
    # document, page 1-on-1): o header `heading_2` com a data e os blocos
    # seguintes até o próximo header.
    #
    # É o conceito que os chamadores reconstruíam à mão a cada uso: antes eles
    # recebiam blocos crus e recompunham "onde começa e onde acaba a seção"
    # combinando predicados. A leitura agora entrega a seção pronta.
    #
    # A ordem do documento não é assumida: uma seção vai do seu header até o
    # próximo header, qualquer que seja a data dele. Isso mantém a leitura
    # válida para o Brag (decrescente) e para o 1-on-1 (crescente).
    class Section
      # Todos os blocos, header incluso, na ordem da page.
      attr_reader :blocks

      def initialize(blocks)
        @blocks = blocks
      end

      # Data do header, ou nil se o texto não for uma data.
      def day = PageDays.day_of(header)

      def header = blocks.first

      def header_id = header&.fetch("id")

      # Blocos da seção sem o header. No Brag o primeiro deles é o sentinel.
      def body = blocks.drop(1)

      # Último bloco da seção — âncora para inserir a seção seguinte (a ordem
      # decrescente do Brag depende de "depois do fim desta seção").
      def last_id = blocks.last&.fetch("id")

      def empty? = blocks.empty?
    end
  end
end
