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

  def entrega_jira(external_id, title = "ENG-1: Resumo", detail: nil, context: [])
    Tracking::Entities::Delivery.new(
      source: :jira, kind: :card_movido, title: title, detail: detail, context: context,
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

    it "põe o detail em negrito, antes do título" do
      repository.append(dia, [ entrega_jira("ENG-1:10001:status", "ENG-1 — Resumo", detail: "In Progress → Review") ])

      blocos = blocos_enviados { repository.append(dia, [ entrega_jira("ENG-1:10001:status", "ENG-1 — Resumo", detail: "In Progress → Review") ]) }
      textos = blocos[1][:bulleted_list_item][:rich_text]
      expect(textos[1][:text][:content]).to eq("In Progress → Review ")
      expect(textos[1][:annotations]).to eq(bold: true)
      expect(textos[2][:text][:content]).to eq("ENG-1 — Resumo")
    end

    it "põe o contexto como sub-bullets aninhados no bullet" do
      contexto = [ "História · [Motor][Wave2] Pagamento", "Quem criou a venda pode cobrá-la depois." ]
      blocos = blocos_enviados do
        repository.append(dia, [ entrega_jira("ENG-1:10001:status", "ENG-1 — Resumo", context: contexto) ])
      end

      filhos = blocos[1][:bulleted_list_item][:children]
      expect(filhos.map { |f| f[:bulleted_list_item][:rich_text][0][:text][:content] }).to eq(contexto)
    end

    it "não cria children quando não há contexto" do
      blocos = blocos_enviados { repository.append(dia, [ entrega_jira("ENG-1:10001:status") ]) }

      expect(blocos[1][:bulleted_list_item][:children]).to eq([])
    end

    it "envia em lotes de 100 blocks (teto da API do Notion)" do
      # Os sub-bullets vão aninhados DENTRO do bullet, então cada entrega é
      # 1 block de topo: 150 entregas + header = 151 → lotes de 100 e 51.
      entregas = Array.new(150) { |i| entrega_jira("ENG-#{i}:1:status", "ENG-#{i} — Resumo", context: [ "linha 1", "linha 2" ]) }

      lotes = lotes_enviados { repository.append(dia, entregas) }

      expect(lotes).to eq([ 100, 51 ])
    end

    it "não estoura o teto quando o dia inteiro passa de 100 entregas" do
      entregas = Array.new(101) { |i| entrega_jira("ENG-#{i}:1:status") }

      lotes = lotes_enviados { repository.append(dia, entregas) }

      expect(lotes).to all(be <= 100)
      expect(lotes.sum).to eq(102) # 101 entregas + header
    end
  end

  # Tamanhos dos lotes enviados durante o exemplo.
  def lotes_enviados
    tamanhos = []
    allow(client).to receive(:append_block_children) { |_, children| tamanhos << children.size }
    yield
    tamanhos
  end

  # Captura os blocos enviados durante o exemplo (achatando os lotes). O
  # índice 0 é o header do dia, que vai junto no primeiro append.
  def blocos_enviados
    enviados = []
    allow(client).to receive(:append_block_children) { |_, children| enviados.concat(children) }
    yield
    enviados
  end
end
