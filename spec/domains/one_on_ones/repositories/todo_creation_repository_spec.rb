# frozen_string_literal: true

require "rails_helper"

RSpec.describe OneOnOnes::Repositories::TodoCreationRepository do
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:repository) { described_class.new(client: client, database_id: "db-todos") }

  describe "#create_todo" do
    it "cria row no To-Dos com Status Pendente e Origem Via Transcrição" do
      allow(client).to receive(:create_page).and_return({ "id" => "page-1" })

      repository.create_todo("André: Assinar Newsletter")

      expect(client).to have_received(:create_page).with(
        database_id: "db-todos",
        properties: {
          "Name" => { title: [ { text: { content: "André: Assinar Newsletter" } } ] },
          "Status" => { status: { name: "Pendente" } },
          "Origem" => { select: { name: "Via Transcrição" } }
        }
      )
    end

    it "aceita origem customizada" do
      allow(client).to receive(:create_page).and_return({ "id" => "page-1" })

      repository.create_todo("título", origin: "Manual")

      expect(client).to have_received(:create_page).with(
        database_id: "db-todos",
        properties: hash_including("Origem" => { select: { name: "Manual" } })
      )
    end
  end
end
