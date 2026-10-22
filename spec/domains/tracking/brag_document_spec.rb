# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Tracking::BragDocument do
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:dir) { Dir.mktmpdir }
  let(:logger) { instance_double(ActiveSupport::Logger, warn: nil, error: nil, info: nil) }
  let(:stdout) { StringIO.new }
  let(:ledger) do
    Tracker::Brag::BlockLedger.new(path: File.join(dir, "state.json"), page_id: "page-brag", logger:)
  end
  let(:brag) do
    described_class.new(client:, page_id: "page-brag", ledger:, logger:, stdout:)
  end
  let(:dia) { Date.new(2026, 10, 21) }

  after { FileUtils.remove_entry(dir) }

  def item(texto: "#2301 · card")
    Tracking::Entities::WorkItem.new(
      key: "CHEKOUT-2301", title: texto, url: "https://jira/browse/CHEKOUT-2301", mine: true,
      outcome: :merged, outcome_at: Time.zone.parse("#{dia} 16:48"), pull_requests: []
    )
  end

  def report(items: [ item ], epic_note: nil)
    Tracking::Entities::DayReport.new(date: dia, epic_note:, work_items: items)
  end

  # Stub do client que simula ids novos a cada append e respeita a posição.
  def stub_client(existentes: [])
    sequencia = 0
    allow(client).to receive(:block_children).and_return(existentes)
    allow(client).to receive(:append_block_children) do |_page, children, after: nil|
      registros = children.map do
        sequencia += 1
        { "id" => "novo-#{sequencia}" }
      end
      { "results" => registros }
    end
    allow(client).to receive(:delete_block) { { "object" => "block" } }
  end

  # Captura os blocos enviados; header id h1, sentinel h2, body h3+.
  def capturar_appends
    envios = []
    allow(client).to receive(:block_children).and_return([])
    allow(client).to receive(:append_block_children) do |_page, children, after: nil|
      envios.concat(children)
      { "results" => Array.new(children.size) { |i| { "id" => "blk-#{envios.size - children.size + i}" } } }
    end
    allow(client).to receive(:delete_block) { { "object" => "block" } }
    envios
  end

  def header(content) = { "id" => "h-#{content}", "type" => "heading_2",
                          "heading_2" => { "rich_text" => [ { "plain_text" => content } ] } }

  describe "#rewrite" do
    it "cria header e sentinel na primeira vez e grava o body" do
      stub_client

      expect(brag.rewrite(dia, report)).to eq(:reescrito)

      expect(client).to have_received(:append_block_children).with("page-brag", [ hash_including(type: "heading_2") ], after: nil)
      expect(client).to have_received(:append_block_children).with("page-brag", [ hash_including(type: "paragraph") ], after: "novo-1")
      expect(client).to have_received(:append_block_children).with("page-brag", anything, after: "novo-2")
    end

    it "monta o header com a data e o épico (sem o chamador saber do formato)" do
      blocos = capturar_appends

      brag.rewrite(dia, report(epic_note: "[Motor][Wave2] Pagamento"))

      header = blocos.find { |b| b[:type] == "heading_2" }
      expect(header[:heading_2][:rich_text].first[:text][:content]).to eq("21/10/2026 — quarta · [Motor][Wave2] Pagamento")
    end

    it "não escreve nada quando o conteúdo é idêntico (idempotência)" do
      stub_client
      brag.rewrite(dia, report)
      RSpec::Mocks.space.proxy_for(client).reset
      allow(client).to receive(:block_children).and_return([])
      allow(client).to receive(:append_block_children)
      allow(client).to receive(:delete_block)

      expect(brag.rewrite(dia, report)).to eq(:sem_mudanca)
      expect(client).not_to have_received(:append_block_children)
      expect(client).not_to have_received(:delete_block)
    end

    it "apaga só os blocos do ledger e reescreve quando mudou" do
      stub_client
      brag.rewrite(dia, report)          # header=novo-1, sentinel=novo-2, body=novo-3
      allow(client).to receive(:delete_block)

      brag.rewrite(dia, report(items: [ item(texto: "outro") ]))

      expect(client).to have_received(:delete_block).with("novo-3")
      expect(client).not_to have_received(:delete_block).with("novo-1")
      expect(client).not_to have_received(:delete_block).with("novo-2")
    end

    it "NUNCA apaga bloco desconhecido (escrito à mão na seção)" do
      manual = { "id" => "manual-1", "type" => "paragraph",
                 "paragraph" => { "rich_text" => [ { "plain_text" => "minha nota" } ] } }
      allow(client).to receive(:block_children).and_return([ manual ])
      allow(client).to receive(:append_block_children) { |_, children, after: nil| { "results" => children.map { { "id" => "novo-1" } } } }
      allow(client).to receive(:delete_block)

      brag.rewrite(dia, report)

      expect(client).not_to have_received(:delete_block).with("manual-1")
    end

    it "reaproveita o header existente no documento quando o ledger sumiu" do
      stub_client(existentes: [ header("21/10/2026 — quarta") ])

      brag.rewrite(dia, report)

      expect(client).to have_received(:append_block_children).with("page-brag", [ hash_including(type: "paragraph") ], after: "h-21/10/2026 — quarta")
      expect(client).not_to have_received(:append_block_children).with("page-brag", [ hash_including(type: "heading_2") ], after: nil)
    end

    it "envia em lotes de 100 e encadeia a posição entre lotes (não inverte a ordem)" do
      stub_client
      posicoes = []
      allow(client).to receive(:append_block_children) do |_page, children, after: nil|
        posicoes << [ children.size, after ]
        { "results" => children.map { { "id" => "x#{posicoes.size}-#{children.size}" } } }
      end

      brag.rewrite(dia, report(items: Array.new(150) { |i| item(texto: "item #{i}") }))

      lotes = posicoes.last(2)
      expect(lotes.map(&:first)).to eq([ 100, 50 ])
      # O `after` do 2º lote é o ÚLTIMO id do 1º lote (x3-100), não o sentinel:
      # ancorar no mesmo ponto inverteria a ordem do dia.
      expect(lotes.last.last).to eq("x3-100")
    end

    it "não grava signature nil quando a API devolve mais ids que blocos" do
      allow(client).to receive(:block_children).and_return([])
      allow(client).to receive(:append_block_children) do |_page, children, after: nil|
        { "results" => Array.new(children.size + 1) { |i| { "id" => "x#{i}" } } }
      end
      allow(client).to receive(:delete_block)

      brag.rewrite(dia, report)

      assinaturas = ledger.day(dia)[:blocks].map { |b| b[:signature] }
      expect(assinaturas).to all(be_a(String))
      expect(assinaturas.size).to eq(1)
    end

    it "reaproveita o sentinel já existente em vez de criar outro" do
      sentinel_existente = { "id" => "s-antigo", "type" => "paragraph",
                             "paragraph" => { "rich_text" => [ { "plain_text" => Tracking::Renderers::BragBlocks::SENTINEL } ] } }
      sequencia = 0
      allow(client).to receive(:block_children).and_return([ header("21/10/2026 — quarta"), sentinel_existente ])
      allow(client).to receive(:append_block_children) do |_page, _children, after: nil|
        sequencia += 1
        { "results" => [ { "id" => "novo-#{sequencia}" } ] }
      end
      allow(client).to receive(:delete_block)

      brag.rewrite(dia, report)

      # Só o body foi escrito: o sentinel não foi recriado.
      expect(client).to have_received(:append_block_children).once
      expect(ledger.day(dia)[:sentinel_id]).to eq("s-antigo")
    end

    it "sem ledger mas com sentinel, adota os blocos da seção (não duplica)" do
      sentinel_existente = { "id" => "s-1", "type" => "paragraph",
                             "paragraph" => { "rich_text" => [ { "plain_text" => Tracking::Renderers::BragBlocks::SENTINEL } ] } }
      orfao = { "id" => "b-antigo", "type" => "bulleted_list_item",
                "bulleted_list_item" => { "rich_text" => [ { "plain_text" => "conteúdo gerado antes" } ] } }
      vizinho = header("22/10/2026 — quinta")
      allow(client).to receive(:block_children).and_return([ header("21/10/2026 — quarta"), sentinel_existente, orfao, vizinho ])
      allow(client).to receive(:append_block_children) { |_p, c, after: nil| { "results" => c.map { { "id" => "novo" } } } }
      allow(client).to receive(:delete_block)

      brag.rewrite(dia, report)

      # O bloco gerado antes (abaixo do sentinel) foi apagado; o de outro dia não.
      expect(client).to have_received(:delete_block).with("b-antigo")
      expect(client).not_to have_received(:delete_block).with("h-22/10/2026 — quinta")
    end

    it "dia vazio sem seção no ledger não cria seção vazia" do
      stub_client

      expect(brag.rewrite(dia, report(items: []))).to eq(:sem_atividade)
      expect(client).not_to have_received(:append_block_children)
    end

    it "dia que já teve seção e agora está vazio grava o 'sem atividade'" do
      stub_client
      brag.rewrite(dia, report)
      allow(client).to receive(:delete_block)

      expect(brag.rewrite(dia, report(items: []))).to eq(:reescrito)
      expect(client).to have_received(:delete_block)
    end
  end

  describe "#adopt" do
    it "marca a seção antiga no ledger e faz backup em storage" do
      allow(client).to receive(:block_children).and_return([
        header("21/10/2026 — quarta"),
        { "id" => "b-antigo", "type" => "bulleted_list_item",
          "bulleted_list_item" => { "rich_text" => [ { "plain_text" => "evento antigo" } ] } }
      ])

      expect(brag.adopt(dia)).to eq(1)
      expect(ledger.day(dia)[:header_id]).to eq("h-21/10/2026 — quarta")
      expect(ledger.day(dia)[:blocks].map { |b| b[:id] }).to eq([ "b-antigo" ])
      expect(stdout.string).to include("adotada")
    end

    it "não faz nada quando o dia não tem seção" do
      allow(client).to receive(:block_children).and_return([])

      expect(brag.adopt(dia)).to eq(0)
      expect(ledger.day(dia)).to be_nil
    end
  end
end
