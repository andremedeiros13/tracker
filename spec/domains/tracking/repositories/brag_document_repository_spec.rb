# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Tracking::Repositories::BragDocumentRepository do
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:dir) { Dir.mktmpdir }
  let(:ledger) { Tracker::Tracking::BlockLedger.new(path: File.join(dir, "state.json"), page_id: "page-brag",
                                                    logger: instance_double(ActiveSupport::Logger, warn: nil, error: nil)) }
  let(:repository) { described_class.new(client: client, page_id: "page-brag", ledger: ledger,
                                         logger: instance_double(ActiveSupport::Logger, warn: nil, error: nil)) }
  let(:dia) { Date.new(2026, 10, 21) }
  let(:header) { { object: "block", type: "heading_2", heading_2: { rich_text: [ { type: "text", text: { content: "21/10/2026 — quarta" } } ] } } }
  let(:sentinel) { { object: "block", type: "paragraph", paragraph: { rich_text: [ { type: "text", text: { content: "gerado pelo Tracker" } } ] } } }

  after { FileUtils.remove_entry(dir) }

  def bloco(texto)
    { object: "block", type: "bulleted_list_item",
      bulleted_list_item: { rich_text: [ { type: "text", text: { content: texto } } ] } }
  end

  def blocos(*textos) = textos.map { |t| bloco(t) }

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

  describe "#rebuild" do
    it "cria header e sentinel na primeira vez e grava o body" do
      stub_client

      resultado = repository.rebuild(dia, header: header, sentinel: sentinel, blocos: blocos("a", "b"))

      expect(resultado).to eq(:reescrito)
      expect(client).to have_received(:append_block_children).with("page-brag", [ header ], after: nil)
      expect(client).to have_received(:append_block_children).with("page-brag", [ sentinel ], after: "novo-1")
      expect(client).to have_received(:append_block_children).with("page-brag", anything, after: "novo-2")
    end

    it "não escreve nada quando o conteúdo é idêntico (idempotência)" do
      stub_client
      repository.rebuild(dia, header: header, sentinel: sentinel, blocos: blocos("a", "b"))
      RSpec::Mocks.space.proxy_for(client).reset

      allow(client).to receive(:append_block_children)
      allow(client).to receive(:delete_block)

      resultado = repository.rebuild(dia, header: header, sentinel: sentinel, blocos: blocos("a", "b"))

      expect(resultado).to eq(:sem_mudanca)
      expect(client).not_to have_received(:append_block_children)
      expect(client).not_to have_received(:delete_block)
    end

    it "apaga só os blocos do ledger e reescreve quando mudou" do
      stub_client
      repository.rebuild(dia, header: header, sentinel: sentinel, blocos: blocos("a", "b"))
      allow(client).to receive(:delete_block)

      repository.rebuild(dia, header: header, sentinel: sentinel, blocos: blocos("a", "c"))

      expect(client).to have_received(:delete_block).with("novo-3")
      expect(client).to have_received(:delete_block).with("novo-4")
    end

    it "NUNCA apaga bloco desconhecido (escrito à mão na seção)" do
      manual = { "id" => "manual-1", "type" => "paragraph",
                 "paragraph" => { "rich_text" => [ { "plain_text" => "minha nota" } ] } }
      allow(client).to receive(:block_children).and_return([ manual ])
      allow(client).to receive(:append_block_children) { |_, children, after: nil| { "results" => children.map { |_| { "id" => "novo-1" } } } }
      allow(client).to receive(:delete_block)

      repository.rebuild(dia, header: header, sentinel: sentinel, blocos: blocos("a"))

      expect(client).not_to have_received(:delete_block).with("manual-1")
    end

    it "reaproveita o header existente no documento quando o ledger sumiu" do
      existente = { "id" => "h-existente", "type" => "heading_2",
                    "heading_2" => { "rich_text" => [ { "plain_text" => "21/10/2026 — quarta" } ] } }
      stub_client(existentes: [ existente ])

      repository.rebuild(dia, header: header, sentinel: sentinel, blocos: blocos("a"))

      expect(client).to have_received(:append_block_children).with("page-brag", [ sentinel ], after: "h-existente")
      expect(client).not_to have_received(:append_block_children).with("page-brag", [ header ], after: nil)
    end

    it "envia em lotes de 100 e encadeia a posição entre lotes (não inverte a ordem)" do
      stub_client
      posicoes = []
      allow(client).to receive(:append_block_children) do |_page, children, after: nil|
        posicoes << [ children.size, after ]
        { "results" => children.map { |_| { "id" => "x#{posicoes.size}-#{children.size}" } } }
      end

      repository.rebuild(dia, header: header, sentinel: sentinel, blocos: blocos(*Array.new(150) { |i| "item #{i}" }))

      lotes = posicoes.last(2)
      expect(lotes.map(&:first)).to eq([ 100, 50 ])
      # O `after` do 2º lote é o ÚLTIMO id do 1º lote (x3-100), não o sentinel:
      # ancorar no mesmo ponto inverteria a ordem do dia.
      expect(lotes.last.last).to eq("x3-100")
    end

    it "dia vazio ainda grava sentinel e limpa o body" do
      stub_client
      repository.rebuild(dia, header: header, sentinel: sentinel, blocos: blocos("a"))
      allow(client).to receive(:delete_block)

      expect(repository.rebuild(dia, header: header, sentinel: sentinel, blocos: [])).to eq(:reescrito)
      expect(client).to have_received(:delete_block)
    end
  end
end
