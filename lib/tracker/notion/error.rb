# frozen_string_literal: true

module Tracker
  module Notion
    # Erro de domínio do Notion — base própria (o Notion client veio antes de
    # Tracker::Error; o ciclo do scheduler resgata ambos via Tracker::Error).
    class Error < StandardError; end
  end
end
