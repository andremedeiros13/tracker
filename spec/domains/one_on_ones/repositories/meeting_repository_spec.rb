# frozen_string_literal: true

require "rails_helper"

RSpec.describe OneOnOnes::Repositories::MeetingRepository do
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:repository) { described_class.new(client: client, page_id: "page-1o1") }
  let(:dia) { Date.new(2026, 9, 23) }

  def meeting(summary: "Tema discutido.")
    OneOnOnes::Entities::Meeting.new(
      date: dia, title: "1:1 André / Spalenza",
      participants: [ "André Medeiros", "Rodolfo Spalenza" ],
      summary: summary, source_file: nil
    )
  end

  def action_item(owner:, mine:, description: "Tarefa: fazer algo.")
    OneOnOnes::Entities::ActionItem.new(
      meeting: nil, description: description, owner: owner, mine: mine
    )
  end

  def header(content)
    { "id" => "h-#{content}", "type" => "heading_2",
      "heading_2" => { "rich_text" => [ { "plain_text" => content } ] } }
  end

  before do
    allow(client).to receive(:block_children).and_return([])
    allow(client).to receive(:append_block_children).and_return({ "results" => [] })
  end

  describe "#append" do
    it "appenda header do dia + título da reunião + resumo + action items" do
      repository.append(meeting, [ action_item(owner: "André Medeiros", mine: true),
                                   action_item(owner: "Rodolfo Spalenza", mine: false) ])

      expect(client).to have_received(:append_block_children).with("page-1o1", [
        hash_including(type: "heading_2"),
        hash_including(type: "heading_3", heading_3: hash_including(
          rich_text: [ hash_including(text: hash_including(content: "1:1 André / Spalenza")) ]
        )),
        *Array.new(1) { hash_including(type: "paragraph") },
        hash_including(type: "bulleted_list_item", bulleted_list_item: hash_including(
          rich_text: [ hash_including(text: hash_including(content: a_string_including("✅ [André Medeiros]"))) ]
        )),
        hash_including(type: "bulleted_list_item", bulleted_list_item: hash_including(
          rich_text: [ hash_including(text: hash_including(content: a_string_including("👤 [Rodolfo Spalenza]"))) ]
        ))
      ])
    end

    it "não appenda header quando o dia já tem header" do
      allow(client).to receive(:block_children).and_return([ header("23/09/2026") ])

      repository.append(meeting, [])

      children = nil
      expect(client).to have_received(:append_block_children) { |_, blocks| children = blocks }
      expect(children.map { |b| b[:type] }).not_to include("heading_2")
    end

    it "não appenda parágrafos quando o resumo é vazio" do
      repository.append(meeting(summary: ""), [])

      children = nil
      expect(client).to have_received(:append_block_children) { |_, blocks| children = blocks }
      expect(children.map { |b| b[:type] }).not_to include("paragraph")
    end

    # O import escreve aqui e só depois move o arquivo: se algo falhar no meio,
    # a mesma reunião chega de novo no ciclo seguinte.
    it "não appenda duas vezes a mesma reunião no mesmo dia (idempotência)" do
      allow(client).to receive(:block_children).and_return([
        header("23/09/2026"),
        { "id" => "h-titulo", "type" => "heading_3",
          "heading_3" => { "rich_text" => [ { "plain_text" => "1:1 André / Spalenza" } ] } }
      ])

      expect(repository.append(meeting, [])).to be(false)
      expect(client).not_to have_received(:append_block_children)
    end

    it "appenda quando o dia já tem outra reunião (título diferente)" do
      allow(client).to receive(:block_children).and_return([
        header("23/09/2026"),
        { "id" => "h-outro", "type" => "heading_3",
          "heading_3" => { "rich_text" => [ { "plain_text" => "1:1 André / Alguém" } ] } }
      ])

      repository.append(meeting, [])

      expect(client).to have_received(:append_block_children).once
    end
  end
end
