# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracker::Notion::SchemaValidator do
  let(:client) { instance_double(Tracker::Notion::Client) }

  def validator(expected = Todos::Repositories::NotionSchema::PROPERTIES)
    described_class.new(client: client, expected: expected)
  end

  def database_props(properties)
    { "properties" => properties }
  end

  it "passa quando o Database tem o schema esperado" do
    properties = {
      "Name" => { "type" => "title" },
      "Status" => { "type" => "status", "status" => { "options" => [ { "name" => "Pendente" }, { "name" => "Em andamento" }, { "name" => "Concluída" } ] } },
      "Origem" => { "type" => "select", "select" => { "options" => [ { "name" => "Manual" }, { "name" => "Via Jira" }, { "name" => "Via Transcrição" } ] } },
      "Snoozed até" => { "type" => "date" }
    }
    allow(client).to receive(:retrieve_database).and_return(database_props(properties))

    expect { validator.validate! }.not_to raise_error
  end

  it "falha quando uma propriedade está ausente" do
    allow(client).to receive(:retrieve_database).and_return(database_props({}))

    expect { validator.validate! }
      .to raise_error(Tracker::Notion::SchemaError, /propriedade 'Name' \(name\) ausente/)
  end

  it "falha quando o tipo diverge" do
    properties = { "Name" => { "type" => "rich_text" } }
    allow(client).to receive(:retrieve_database).and_return(database_props(properties))

    expect { validator.validate! }
      .to raise_error(Tracker::Notion::SchemaError, /tipo 'rich_text' != 'title'/)
  end

  it "falha quando opções estão faltando" do
    properties = { "Status" => { "type" => "status", "status" => { "options" => [ { "name" => "Pendente" } ] } } }
    allow(client).to receive(:retrieve_database).and_return(database_props(properties))

    expect { validator.validate! }
      .to raise_error(Tracker::Notion::SchemaError, /opções ausentes Em andamento, Concluída/)
  end
end
