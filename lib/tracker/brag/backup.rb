# frozen_string_literal: true

module Tracker
  module Brag
    # Dump em texto de uma seção do Brag, antes de uma operação destrutiva.
    #
    # Existe porque havia duas cópias da mesma conversão (bloco → "tipo: texto")
    # no rewrite/adopt e na migração de ordem (`BragDocument#repair_order`).
    # `PageDays.text_of` já era única;
    # o formato do dump não era — e os dois backups precisam ser legíveis e
    # iguais para quem for comparar o antes e o depois.
    #
    # Um bloco por linha: o leitor cola isso em outro lugar se precisar.
    module Backup
      module_function

      # Grava a seção e devolve o caminho. `suffix` distingue o backup da
      # adoção do backup da migração de ordem (um não deve sobrescrever o
      # outro: o conteúdo perdido em cada um é diferente).
      def section(day, blocks, suffix: nil)
        dir = Rails.root.join("storage/tracking")
        FileUtils.mkdir_p(dir)
        caminho = dir.join("brag_#{day.iso8601}#{suffix}.bak")
        File.write(caminho, to_text(blocks))
        caminho
      end

      def to_text(blocks)
        blocks.map { |b| "#{b.fetch('type')}: #{Tracker::Notion::PageDays.text_of(b)}" }.join("\n")
      end
    end
  end
end
