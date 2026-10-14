# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Repositories::JiraDeliveryRepository do
  let(:client) { instance_double(Tracker::Jira::Client) }
  let(:repository) { described_class.new(client: client, account_id: "acc-1", reviewer_field_id: "customfield_10000") }
  let(:dia) { Date.new(2026, 10, 14) }

  def issue(key, summary = "Resumo do card")
    { "key" => key, "fields" => { "summary" => summary } }
  end

  def changelog_entrada(id:, account_id:, created:, items:)
    { "id" => id, "author" => { "accountId" => account_id }, "created" => created, "items" => items }
  end

  def item(field_id, to_string = "In Progress")
    { "field" => "Status", "fieldId" => field_id, "from" => nil, "fromString" => "", "to" => nil, "toString" => to_string }
  end

  before do
    allow(client).to receive(:search).and_return([ issue("ENG-1") ])
    allow(client).to receive(:changelog).and_return([])
  end

  describe "#entregas_do_dia" do
    it "coleta card movido pelo engenheiro no dia (status no changelog)" do
      allow(client).to receive(:changelog).and_return([
        changelog_entrada(id: "10001", account_id: "acc-1", created: "2026-10-14T10:00:00.000+0000", items: [ item("status") ]),
        changelog_entrada(id: "10002", account_id: "outro", created: "2026-10-14T10:00:00.000+0000", items: [ item("status") ])
      ])

      entregas = repository.entregas_do_dia(dia)

      expect(entregas.size).to eq(1)
      expect(entregas.first).to have_attributes(
        source: :jira, kind: :card_movido, external_id: "ENG-1:10001:status",
        url: a_string_including("browse/ENG-1")
      )
      expect(entregas.first.title).to include("ENG-1")
    end

    it "exclui mudanças de outros dias" do
      allow(client).to receive(:changelog).and_return([
        changelog_entrada(id: "10001", account_id: "acc-1", created: "2026-10-13T10:00:00.000+0000", items: [ item("status") ])
      ])

      expect(repository.entregas_do_dia(dia)).to be_empty
    end

    it "coleta mudança no campo Reviewer (customfield via changelog)" do
      allow(client).to receive(:changelog).and_return([
        changelog_entrada(id: "10003", account_id: "acc-1", created: "2026-10-14T11:00:00.000+0000",
                          items: [ item("customfield_10000", "acc-2") ])
      ])

      entregas = repository.entregas_do_dia(dia)

      expect(entregas.first.kind).to eq(:reviewer)
    end

    it "ignora o campo Reviewer quando JIRA_REVIEWER_FIELD_ID não está configurado" do
      repository_sem_reviewer = described_class.new(client: client, account_id: "acc-1", reviewer_field_id: nil)
      allow(client).to receive(:changelog).and_return([
        changelog_entrada(id: "10003", account_id: "acc-1", created: "2026-10-14T11:00:00.000+0000",
                          items: [ item("customfield_10000", "acc-2") ])
      ])

      expect(repository_sem_reviewer.entregas_do_dia(dia)).to be_empty
    end

    it "busca issues com JQL de janela de 2 dias" do
      repository.entregas_do_dia(dia)

      expect(client).to have_received(:search).with("updated >= -2d ORDER BY updated DESC")
    end

    it "agrega entregas de múltiplos issues" do
      allow(client).to receive(:search).and_return([ issue("ENG-1"), issue("ENG-2") ])
      allow(client).to receive(:changelog) do |key|
        [ changelog_entrada(id: "10001", account_id: "acc-1", created: "2026-10-14T10:00:00.000+0000", items: [ item("status") ]) ]
      end

      expect(repository.entregas_do_dia(dia).map(&:external_id)).to eq(
        [ "ENG-1:10001:status", "ENG-2:10001:status" ]
      )
    end
  end
end
