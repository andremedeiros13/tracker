# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Repositories::JiraDayRepository do
  let(:client) { instance_double(Tracker::Jira::Client) }
  let(:dia) { Date.new(2026, 10, 21) }

  def repository(filtro: "estreito")
    described_class.new(client: client, site: "https://jira.example.com", account_id: "acc-eu",
                        reviewer_field_id: nil, filtro:)
  end

  def card(id: "id-1", key: "CHEKOUT-1", comentarios: [])
    {
      "id" => id, "key" => key,
      "fields" => {
        "summary" => "Resumo", "status" => { "name" => "Em andamento", "statusCategory" => { "key" => "indeterminate" } },
        "assignee" => { "displayName" => "André", "accountId" => "acc-eu" },
        "reporter" => { "displayName" => "Marivaldo" },
        "parent" => nil, "description" => nil,
        "comment" => { "comments" => comentarios }
      }
    }
  end

  # Entrada no shape do bulkfetch: created em epoch ms, author como accountId.
  def bulkfetch_entry(hora:, author: "acc-eu", items: [ { "fieldId" => "status", "fromString" => "To Do", "toString" => "In Progress" } ])
    { "author" => author, "created" => (Time.zone.parse("#{dia} #{hora}").to_f * 1000).to_i, "items" => items }
  end

  before do
    allow(client).to receive(:search).and_return([ card ])
  end

  describe "#dia" do
    it "normaliza o changelog do bulkfetch: author como id cru e created em epoch" do
      allow(client).to receive(:changelog_em_lote).and_return({ "id-1" => [ bulkfetch_entry(hora: "10:00") ] })

      atividade = repository.dia(dia).activities_for("CHEKOUT-1").first

      expect(atividade).to have_attributes(kind: :changelog, author_id: "acc-eu")
      expect(atividade.at).to eq(Time.zone.parse("#{dia} 10:00"))
      expect(atividade.status_pairs).to eq([ [ "To Do", "In Progress" ] ])
    end

    it "normaliza o changelog individual: author como hash e created em ISO 8601" do
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-1" => [ { "author" => { "accountId" => "acc-eu" },
                      "created" => "#{dia}T10:00:00.000-0300",
                      "items" => [ { "fieldId" => "status", "fromString" => "Review", "toString" => "Done" } ] } ]
      })

      atividade = repository.dia(dia).activities_for("CHEKOUT-1").first

      expect(atividade.author_id).to eq("acc-eu")
      expect(atividade.at).to eq(Time.zone.parse("#{dia} 10:00"))
      expect(atividade.status_pairs).to eq([ [ "Review", "Done" ] ])
    end

    it "inclui comentários como atividade, distinguidos do changelog" do
      allow(client).to receive(:changelog_em_lote).and_return({})
      allow(client).to receive(:search).and_return([
        card(comentarios: [ { "author" => { "accountId" => "acc-eu" }, "created" => "#{dia}T16:46:00-0300" } ])
      ])

      atividades = repository.dia(dia).activities_for("CHEKOUT-1")

      expect(atividades.map(&:kind)).to eq([ :comment ])
      expect(atividades.first.author_id).to eq("acc-eu")
    end

    it "descarta itens de changelog que não são de status" do
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-1" => [ bulkfetch_entry(hora: "10:00", items: [ { "fieldId" => "description", "fromString" => "a", "toString" => "b" } ]) ]
      })

      atividade = repository.dia(dia).activities_for("CHEKOUT-1").first

      expect(atividade).not_to be_touches_status
    end

    it "aceita transição com lado ausente (card criado já numa coluna)" do
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-1" => [ bulkfetch_entry(hora: "10:00", items: [ { "fieldId" => "status", "toString" => "To Do" } ]) ]
      })

      atividade = repository.dia(dia).activities_for("CHEKOUT-1").first

      expect(atividade).to be_touches_status
      expect(atividade.status_pairs).to be_empty
    end

    it "ordena as atividades por instante (changelog e comentário intercalados)" do
      allow(client).to receive(:changelog_em_lote).and_return({ "id-1" => [ bulkfetch_entry(hora: "15:00") ] })
      allow(client).to receive(:search).and_return([
        card(comentarios: [ { "author" => { "accountId" => "acc-eu" }, "created" => "#{dia}T09:00:00-0300" } ])
      ])

      expect(repository.dia(dia).activities_for("CHEKOUT-1").map(&:kind)).to eq([ :comment, :changelog ])
    end

    it "normaliza o card: achata fields e resolve url do browse" do
      allow(client).to receive(:changelog_em_lote).and_return({})

      card_normalizado = repository.dia(dia).cards.first

      expect(card_normalizado).to include(
        "key" => "CHEKOUT-1", "title" => "Resumo", "status" => "Em andamento",
        "assignee_id" => "acc-eu", "url" => "https://jira.example.com/browse/CHEKOUT-1"
      )
    end

    it "sem cards não consulta changelog" do
      allow(client).to receive(:search).and_return([])
      allow(client).to receive(:changelog_em_lote)

      expect(repository.dia(dia)).to be_a(Tracking::Entities::JiraDay)
      expect(client).not_to have_received(:changelog_em_lote)
    end
  end

  describe "filtro JQL" do
    it "estreito: só participação minha (status/assignee/reporter)" do
      allow(client).to receive(:changelog_em_lote).and_return({})

      repository(filtro: "estreito").dia(dia)

      expect(client).to have_received(:search) do |jql, **_|
        expect(jql).to include("status CHANGED BY currentUser()", "assignee = currentUser()")
      end
    end

    it "largo: sem critério de participação (varredura de segurança)" do
      allow(client).to receive(:changelog_em_lote).and_return({})

      repository(filtro: "largo").dia(dia)

      expect(client).to have_received(:search) do |jql, **_|
        expect(jql).not_to include("currentUser()")
      end
    end
  end
end
