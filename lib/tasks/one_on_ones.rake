# frozen_string_literal: true

namespace :one_on_ones do
  desc "Importa os .md soltos na pasta monitorada (resumo na page 1-on-1, action items meus viram To-Dos)"
  task import: :environment do
    importados = OneOnOnes::UseCases::ImportTranscription.new.call
    if importados.zero?
      puts "Nada para importar."
    else
      puts "#{importados} arquivo#{importados > 1 ? "s" : ""} importado#{importados > 1 ? "s" : ""}."
    end
  end
end
