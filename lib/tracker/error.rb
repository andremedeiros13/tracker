# frozen_string_literal: true

module Tracker
  # Erro base do projeto — os clientes (Notion, Jira, GitHub) derivam daqui e
  # o ciclo do scheduler resgata Tracker::Error sem derrubar o daemon.
  class Error < StandardError; end
end
