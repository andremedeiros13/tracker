# frozen_string_literal: true

require "rails_helper"

RSpec.describe Todos::Repositories::TodoDatabase do
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:database) do
    described_class.new(client: client, mapper: Todos::Repositories::PropertyMapper.new,
                        database_id: "db-todos")
  end

  def page_notion(titulo:, status:, snoozed_until: nil, origem: "Manual")
    {
      "id" => "page-#{titulo}",
      "created_time" => "2026-10-09T12:00:00.000Z",
      "last_edited_time" => "2026-10-09T12:00:00.000Z",
      "properties" => {
        "Name" => { "type" => "title", "title" => [ { "plain_text" => titulo } ] },
        "Status" => { "type" => "status", "status" => { "name" => status } },
        "Origem" => { "type" => "select", "select" => { "name" => origem } },
        "Snoozed até" => { "type" => "date", "date" => snoozed_until ? { "start" => snoozed_until } : nil }
      }
    }
  end

  describe "#notification_candidates" do
    before do
      allow(client).to receive(:query_database).and_return([
        page_notion(titulo: "agora", status: "Pendente"),
        page_notion(titulo: "snoozed futuro", status: "Em andamento", snoozed_until: "2099-01-01T12:00:00.000Z"),
        page_notion(titulo: "snoozed vencido", status: "Em andamento", snoozed_until: "2020-01-01T12:00:00.000Z")
      ])
    end

    it "exclui snoozed com horário no futuro e inclui vencido" do
      titulos = database.notification_candidates.map(&:title)

      expect(titulos).to eq([ "snoozed vencido", "agora" ])
    end

    it "consulta o Notion com filtro server-side no Status" do
      database.notification_candidates

      expect(client).to have_received(:query_database).with(
        filter: { or: [
          { property: "Status", status: { equals: "Pendente" } },
          { property: "Status", status: { equals: "Em andamento" } }
        ] }
      )
    end

    it "ordena pelo que vence primeiro (snoozed volta no horário)" do
      allow(client).to receive(:query_database).and_return([
        page_notion(titulo: "criada antes", status: "Pendente"),
        page_notion(titulo: "snoozed vencido", status: "Em andamento", snoozed_until: "2020-01-01T12:00:00.000Z")
      ])

      expect(database.notification_candidates.map(&:title)).to eq([ "snoozed vencido", "criada antes" ])
    end
  end

  describe "#create" do
    before { allow(client).to receive(:create_page).and_return({ "id" => "page-1" }) }

    it "cria row Pendente com a origem de domínio traduzida pelo schema" do
      database.create("André: Assinar Newsletter", origin: :via_transcricao)

      expect(client).to have_received(:create_page).with(
        database_id: "db-todos",
        properties: {
          "Name" => { title: [ { text: { content: "André: Assinar Newsletter" } } ] },
          "Status" => { status: { name: "Pendente" } },
          "Origem" => { select: { name: "Via Transcrição" } }
        }
      )
    end

    it "origem padrão é manual (label vindo do schema)" do
      database.create("título")

      expect(client).to have_received(:create_page).with(
        database_id: "db-todos",
        properties: hash_including("Origem" => { select: { name: "Manual" } })
      )
    end

    it "falha alto quando a origem não existe no schema" do
      expect { database.create("título", origin: :inventada) }.to raise_error(KeyError, /inventada/)
      expect(client).not_to have_received(:create_page)
    end

    # O ponto do módulo: escrita e leitura derivam do mesmo NotionSchema.
    it "os labels escritos são exatamente os que a leitura sabe mapear" do
      escritos = []
      allow(client).to receive(:create_page) { |args| escritos << args; { "id" => "p" } }
      Todos::Repositories::NotionSchema::PROPERTIES.fetch("Origem").fetch(:options).each_value do |valor|
        database.create("t", origin: valor)
      end

      labels = escritos.map { |a| a[:properties]["Origem"][:select][:name] }
      expect(labels).to match_array(Todos::Repositories::NotionSchema::PROPERTIES["Origem"][:options].keys)
    end
  end
end
