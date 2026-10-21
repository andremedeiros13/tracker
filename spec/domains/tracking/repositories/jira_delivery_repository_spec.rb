# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Repositories::JiraDeliveryRepository do
  let(:client) { instance_double(Tracker::Jira::Client) }
  let(:repository) { described_class.new(client: client, account_id: "acc-1", reviewer_field_id: "customfield_10000", filtro: "largo") }
  let(:dia) { Date.new(2026, 10, 14) }

  def issue(key, summary = "Resumo do card")
    { "id" => "id-#{key}", "key" => key, "fields" => { "summary" => summary } }
  end

  # Shape do bulkfetch: "author" é o accountId direto e "created" é epoch ms.
  def changelog_entrada(id:, account_id:, created:, items:)
    { "id" => id, "author" => account_id, "created" => epoch_ms(created), "items" => items }
  end

  def epoch_ms(iso)
    (Time.zone.parse(iso).to_f * 1000).to_i
  end

  def item(field_id, to_string = "In Progress")
    { "field" => "Status", "fieldId" => field_id, "from" => nil, "fromString" => "", "to" => nil, "toString" => to_string }
  end

  before do
    allow(client).to receive(:search).and_return([ issue("ENG-1") ])
    allow(client).to receive(:changelog_em_lote).and_return({})
  end

  describe "#entregas_do_dia" do
    it "coleta card movido pelo engenheiro no dia (status no changelog)" do
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-ENG-1" => [
          changelog_entrada(id: "10001", account_id: "acc-1", created: "2026-10-14T10:00:00.000+0000", items: [ item("status") ]),
          changelog_entrada(id: "10002", account_id: "outro", created: "2026-10-14T10:00:00.000+0000", items: [ item("status") ])
        ]
      })

      entregas = repository.entregas_do_dia(dia)

      expect(entregas.size).to eq(1)
      expect(entregas.first).to have_attributes(
        source: :jira, kind: :card_movido, external_id: "ENG-1:10001:status",
        url: a_string_including("browse/ENG-1")
      )
      expect(entregas.first.title).to include("ENG-1")
    end

    it "exclui mudanças de outros dias" do
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-ENG-1" => [
          changelog_entrada(id: "10001", account_id: "acc-1", created: "2026-10-13T10:00:00.000+0000", items: [ item("status") ])
        ]
      })

      expect(repository.entregas_do_dia(dia)).to be_empty
    end

    it "coleta mudança no campo Reviewer (customfield via changelog)" do
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-ENG-1" => [
          changelog_entrada(id: "10003", account_id: "acc-1", created: "2026-10-14T11:00:00.000+0000",
                            items: [ item("customfield_10000", "acc-2") ])
        ]
      })

      entregas = repository.entregas_do_dia(dia)

      expect(entregas.first.kind).to eq(:reviewer)
    end

    it "ignora o campo Reviewer quando JIRA_REVIEWER_FIELD_ID não está configurado" do
      repository_sem_reviewer = described_class.new(client: client, account_id: "acc-1", reviewer_field_id: nil)
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-ENG-1" => [
          changelog_entrada(id: "10003", account_id: "acc-1", created: "2026-10-14T11:00:00.000+0000",
                            items: [ item("customfield_10000", "acc-2") ])
        ]
      })

      expect(repository_sem_reviewer.entregas_do_dia(dia)).to be_empty
    end

    it "busca issues com JQL de janela de 2 dias" do
      repository.entregas_do_dia(dia)

      expect(client).to have_received(:search).with(
        "updated >= -2d ORDER BY updated DESC",
        fields: "key,summary,issuetype,parent,components,description"
      )
    end

    context "com TRACER_JIRA_FILTRO=estreito" do
      let(:repository) do
        described_class.new(client: client, account_id: "acc-1",
                            reviewer_field_id: "customfield_10125", filtro: "estreito")
      end

      it "restringe a busca à participação do usuário (incluindo o Reviewer)" do
        repository.entregas_do_dia(dia)

        expect(client).to have_received(:search).with(
          "updated >= -2d AND (status CHANGED BY currentUser() OR assignee = currentUser()" \
          " OR reporter = currentUser() OR cf[10125] = currentUser()) ORDER BY updated DESC",
          fields: "key,summary,issuetype,parent,components,description"
        )
      end

      it "omite o critério de Reviewer quando o campo não está configurado" do
        sem_reviewer = described_class.new(client: client, account_id: "acc-1", filtro: "estreito")
        sem_reviewer.entregas_do_dia(dia)

        expect(client).to have_received(:search).with(
          "updated >= -2d AND (status CHANGED BY currentUser() OR assignee = currentUser()" \
          " OR reporter = currentUser()) ORDER BY updated DESC",
          fields: "key,summary,issuetype,parent,components,description"
        )
      end
    end

    it "agrega entregas de múltiplos issues em uma única chamada de lote" do
      allow(client).to receive(:search).and_return([ issue("ENG-1"), issue("ENG-2") ])
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-ENG-1" => [ changelog_entrada(id: "10001", account_id: "acc-1", created: "2026-10-14T10:00:00.000+0000", items: [ item("status") ]) ],
        "id-ENG-2" => [ changelog_entrada(id: "10001", account_id: "acc-1", created: "2026-10-14T10:00:00.000+0000", items: [ item("status") ]) ]
      })

      expect(repository.entregas_do_dia(dia).map(&:external_id)).to eq(
        [ "ENG-1:10001:status", "ENG-2:10001:status" ]
      )
      expect(client).to have_received(:changelog_em_lote).once.with([ "id-ENG-1", "id-ENG-2" ])
    end

    it "não chama o lote quando a busca não retorna issues" do
      allow(client).to receive(:search).and_return([])

      expect(repository.entregas_do_dia(dia)).to be_empty
      expect(client).not_to have_received(:changelog_em_lote)
    end

    it "ignora itens sem fieldId (campo Rank vem só com field/fieldtype)" do
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-ENG-1" => [
          changelog_entrada(id: "10001", account_id: "acc-1", created: "2026-10-14T10:00:00.000+0000", items: [
            { "field" => "Classificação", "fieldtype" => "custom", "fromString" => "", "toString" => "Ranked higher" },
            item("status")
          ])
        ]
      })

      expect(repository.entregas_do_dia(dia).map(&:external_id)).to eq([ "ENG-1:10001:status" ])
    end

    it "aceita o shape do changelog individual (created ISO 8601, author em hash)" do
      allow(client).to receive(:changelog_em_lote).and_return({
        "id-ENG-1" => [
          { "id" => "10001", "author" => { "accountId" => "acc-1" },
            "created" => "2026-10-14T10:00:00.000+0000", "items" => [ item("status") ] }
        ]
      })

      expect(repository.entregas_do_dia(dia).map(&:external_id)).to eq([ "ENG-1:10001:status" ])
    end
  end
end
