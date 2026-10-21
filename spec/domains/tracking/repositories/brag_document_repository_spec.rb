# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Repositories::BragDocumentRepository do
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:repository) { described_class.new(client: client, page_id: "page-brag") }
  let(:dia) { Date.new(2026, 10, 14) }

  def header(content)
    { "id" => "h-#{content}", "type" => "heading_2",
      "heading_2" => { "rich_text" => [ { "plain_text" => content } ] } }
  end

  def bullet(content)
    { "id" => "b-#{content.object_id}", "type" => "bulleted_list_item",
      "bulleted_list_item" => { "rich_text" => [ { "plain_text" => content } ] } }
  end

  def entrega_jira(external_id, title = "ENG-1: Resumo")
    Tracking::Entities::Delivery.new(
      source: :jira, kind: :card_movido, title: title,
      url: "https://jira.example.com/browse/ENG-1", occurred_at: Time.current, external_id: external_id
    )
  end

  describe "#entregas_existentes" do
    it "retorna os external_ids dos bullets do dia (dedup)" do
      allow(client).to receive(:block_children).and_return([
        header("14/10/2026"),
        bullet("[Jira] Movido [ENG-1:10001:status] Resumo"),
        bullet("[GitHub] Commit [abc123] fix")
      ])

      existentes = repository.entregas_existentes(dia)

      expect(existentes.map { |e| e[:external_id] }).to eq([ "ENG-1:10001:status", "abc123" ])
    end

    it "ignora bullets de outros dias (outro header fecha a janela)" do
      allow(client).to receive(:block_children).and_return([
        header("13/10/2026"),
        bullet("[Jira] Movido [ENG-0:9999:status] Antigo"),
        header("14/10/2026"),
        bullet("[Jira] Movido [ENG-1:10001:status] Hoje")
      ])

      existentes = repository.entregas_existentes(dia)

      expect(existentes.map { |e| e[:external_id] }).to eq([ "ENG-1:10001:status" ])
    end

    it "retorna vazio quando o dia não tem header" do
      allow(client).to receive(:block_children).and_return([
        header("13/10/2026"),
        bullet("[Jira] Movido [ENG-0:9999:status] Antigo")
      ])

      expect(repository.entregas_existentes(dia)).to be_empty
    end
  end

  describe "#append" do
    before do
      allow(client).to receive(:block_children).and_return([])
      allow(client).to receive(:append_block_children).and_return({ "results" => [] })
    end

    it "appenda header do dia + bullets com link clicável" do
      repository.append(dia, [ entrega_jira("ENG-1:10001:status") ])

      expect(client).to have_received(:append_block_children).with("page-brag", [
        hash_including(type: "heading_2"),
        hash_including(
          type: "bulleted_list_item",
          bulleted_list_item: hash_including(
            rich_text: [
              hash_including(text: hash_including(content: a_string_including("[ENG-1:10001:status]"))),
              hash_including(text: hash_including(link: { url: "https://jira.example.com/browse/ENG-1" }))
            ]
          )
        )
      ])
    end

    it "não appenda header quando o dia já tem header" do
      allow(client).to receive(:block_children).and_return([ header("14/10/2026") ])
      repository.append(dia, [ entrega_jira("ENG-2:10002:status") ])

      expect(client).to have_received(:append_block_children).with("page-brag", [ hash_including(type: "bulleted_list_item") ])
    end

    it "não chama a API quando não há entregas" do
      repository.append(dia, [])

      expect(client).not_to have_received(:append_block_children)
    end
  end
end
