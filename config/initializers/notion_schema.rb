# frozen_string_literal: true

# ADR 0001: valida as propriedades do Database "To-Dos" contra o schema
# esperado no boot e falha cedo se divergir. O Database é criado manualmente
# no Notion — divergência de schema é erro de setup, não de runtime.
#
# Sem token (CI, primeira execução), a validação acontece no primeiro boot
# com credenciais — nada para validar antes disso.
Rails.application.config.after_initialize do
  next if Rails.env.test? || ENV["CI"] || defined?(Rails::Console)
  next unless ENV["TRACER_NOTION_TOKEN"]

  Tracker::Notion::SchemaValidator.new(
    client: Tracker::Notion::Client.from_env,
    database_id: ENV.fetch("TRACER_NOTION_DATABASE_ID"),
    expected: Todos::Repositories::NotionSchema::PROPERTIES
  ).validate!
end
