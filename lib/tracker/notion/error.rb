# frozen_string_literal: true

module Tracker
  module Notion
    # Erro de domínio do Notion. Deriva de Tracker::Error como os dos outros
    # clientes — assim quem resgata Tracker::Error cobre as três integrações.
    class Error < ::Tracker::Error; end
  end
end
