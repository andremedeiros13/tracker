# frozen_string_literal: true

module OneOnOnes
  module UseCases
    # O ciclo do OneOnOnes: importa os .md soltos na pasta monitorada (ENV
    # TRACER_ONE_ON_ONES_DIR, default: one_on_ones/ na raiz do repo), extrai
    # resumo + action items (parser nativo), appenda o resumo na page 1-on-1
    # e cria To-Dos dos action items meus (matching parcial do nome — ENV
    # TRACER_ONE_ON_ONES_ME). O arquivo importado vai para "importados/" —
    # nunca re-importado.
    #
    # Erro é resgatado e logado — nunca derruba o ciclo do scheduler.
    class ImportTranscription
      DEFAULT_DIR = Rails.root.join("one_on_ones")

      def initialize(dir: ENV["TRACER_ONE_ON_ONES_DIR"] || DEFAULT_DIR,
                     parser: ParseTranscription.new,
                     meetings: Repositories::MeetingRepository.new,
                     todos: Repositories::TodoCreationRepository.new,
                     logger: Rails.logger,
                     me: ENV["TRACER_ONE_ON_ONES_ME"])
        @dir = dir
        @parser = parser
        @meetings = meetings
        @todos = todos
        @logger = logger
        @me = me
      end

      def call
        return 0 if @dir.blank?

        arquivos_novos.sum { |arquivo| importar(arquivo) }
      end

      private

      def arquivos_novos
        Dir.glob(File.join(@dir, "*.md")).reject { |arquivo| File.basename(arquivo).start_with?(".") }
      end

      def importar(arquivo)
        resultado = @parser.call(File.read(arquivo))
        return mover(arquivo) if resultado[:meetings].empty?

        action_items = marcar_meus(resultado[:action_items])
        @meetings.append(resultado[:meetings].first, action_items)

        criados = action_items.select(&:mine?)
        criados.each { |item| @todos.create_todo("#{item.owner}: #{item.description}") }
        mover(arquivo)
        criados.size
      rescue Tracker::Error, Tracker::Notion::Error, KeyError => e
        @logger.error("[one-on-ones] #{File.basename(arquivo)}: #{e.class}: #{e.message}")
        0
      end

      # Matching parcial: "André Medeiros" casa "André Medeiros" e "André" —
      # o nome varia entre reuniões (decisão #14, adaptada).
      def marcar_meus(action_items)
        return action_items if @me.blank?

        action_items.map do |item|
          dono = item.owner.downcase
          meu = dono.include?(@me.downcase) || @me.downcase.include?(dono)
          item.with(mine: meu)
        end
      end

      # Dedup + histórico local: importado/ nunca é re-importado.
      def mover(arquivo)
        importados = File.join(@dir, "importados")
        FileUtils.mkdir_p(importados)
        FileUtils.mv(arquivo, File.join(importados, File.basename(arquivo)))
      end
    end
  end
end
