# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracker::Notion::PageDays do
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:page_days) { described_class.new(client: client, page_id: "page-1") }
  let(:dia) { Date.new(2026, 10, 21) }

  def bloco(id:, type: "bulleted_list_item", texto: "conteúdo")
    { "id" => id, "type" => type, type => { "rich_text" => [ { "plain_text" => texto } ] } }
  end

  def header(id: "h1", texto: "21/10/2026 — quarta")
    bloco(id:, type: "heading_2", texto:)
  end

  def ids(secao) = secao.body.map { |b| b.fetch("id") }

  before do
    allow(client).to receive(:block_children).and_return([
      header(id: "h1", texto: "20/10/2026 — terça"),
      bloco(id: "b-ontem", texto: "ontem"),
      header(id: "h2", texto: "21/10/2026 — quarta"),
      bloco(id: "b1", texto: "hoje 1"),
      bloco(id: "b2", texto: "hoje 2"),
      header(id: "h3", texto: "22/10/2026 — quinta"),
      bloco(id: "b-amanha")
    ])
  end

  describe "#section" do
    it "entrega a seção do dia: header e body até o próximo header" do
      secao = page_days.section(dia)

      expect(secao.header_id).to eq("h2")
      expect(secao.day).to eq(dia)
      expect(ids(secao)).to eq(%w[b1 b2])
    end

    it "funciona em página decrescente (a seção termina no dia ANTERIOR)" do
      allow(client).to receive(:block_children).and_return([
        header(id: "h2", texto: "21/10/2026 — quarta"),
        bloco(id: "b1"),
        header(id: "h1", texto: "20/10/2026 — terça"),
        bloco(id: "b-ontem")
      ])

      secao = page_days.section(dia)

      expect(secao.header_id).to eq("h2")
      expect(ids(secao)).to eq(%w[b1])
    end

    it "aceita uma leitura já feita em `blocks:` (sem ir ao client)" do
      leitura = [ header(id: "h2", texto: "21/10/2026 — quarta"), bloco(id: "b1") ]

      expect(ids(page_days.section(dia, blocks: leitura))).to eq(%w[b1])
      expect(client).not_to have_received(:block_children)
    end

    it "dia sem seção devolve nil" do
      expect(page_days.section(Date.new(2020, 1, 1))).to be_nil
    end
  end

  describe "#sections" do
    it "lista as seções na ordem da página, cada uma com o seu dia" do
      secoes = page_days.sections

      expect(secoes.map(&:day)).to eq([ Date.new(2026, 10, 20), dia, Date.new(2026, 10, 22) ])
      expect(secoes.map(&:header_id)).to eq(%w[h1 h2 h3])
    end

    it "ignora blocos antes do primeiro header" do
      allow(client).to receive(:block_children).and_return([
        bloco(id: "solta", texto: "sem seção"),
        header(id: "h1", texto: "21/10/2026 — quarta"),
        bloco(id: "b1")
      ])

      secoes = page_days.sections

      expect(secoes.size).to eq(1)
      expect(ids(secoes.first)).to eq(%w[b1])
    end

    it "uma leitura só, para qualquer número de seções" do
      page_days.sections

      expect(client).to have_received(:block_children).once
    end
  end

  describe ".day_of" do
    # Compatibilidade: headers escritos antes de o épico sair da copy ainda
    # estão na página. A leitura é por prefixo, então os dois formatos passam.
    it "lê a data do header legado (com o épico que hoje não é mais escrito)" do
      expect(described_class.day_of(header(texto: "21/10/2026 — quarta · [Motor][Wave2] Pagamento")))
        .to eq(dia)
    end

    it "lê o header sem sufixo (formato do 1-on-1)" do
      expect(described_class.day_of(header(texto: "21/10/2026"))).to eq(dia)
    end

    it "devolve nil para header sem data e para bloco que não é header" do
      expect(described_class.day_of(header(texto: "sem data aqui"))).to be_nil
      expect(described_class.day_of(bloco(id: "b1"))).to be_nil
    end
  end

  describe ".text_of" do
    it "extrai plain_text do payload da API" do
      expect(described_class.text_of(header)).to eq("21/10/2026 — quarta")
    end

    it "também aceita rich_text no shape do renderer (chaves símbolo)" do
      bloco_renderer = { "type" => "paragraph",
                         "paragraph" => { rich_text: [ { text: { content: "olá" } } ] } }

      expect(described_class.text_of(bloco_renderer)).to eq("olá")
    end
  end

  describe ".marker" do
    it "é o formato único de data das duas pages" do
      expect(described_class.marker(dia)).to eq("21/10/2026")
    end
  end
end
